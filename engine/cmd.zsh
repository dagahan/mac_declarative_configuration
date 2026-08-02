typeset -gA ST RSN SKIP
typeset -ga SELECTED
typeset -g REASON='' LAST_OUTPUT=''
typeset -gi VERBOSE=0 ASSUME_YES=0 ROOT_OPTIONAL=0

target_of() { print -r -- "${1#*:}" }

describe() {
    local id=$1 d
    d=$(provider_call describe "$id" 2>/dev/null) || d=''
    print -r -- "${d:-$(target_of "$id")}"
}

# A selector is a unit name, or a resource-id glob when it contains a colon.
select_ids() {
    SELECTED=()
    local id u
    if (( $# == 0 )); then
        for id in "${ORDERED[@]}"; do
            [[ -n "${U_OPTIN[${R_UNIT[$id]}]:-}" ]] && continue
            SELECTED+=("$id")
        done
        return
    fi
    for u in "$@"; do
        [[ "$u" == *:* ]] && continue
        unit_exists "$u" || die "unknown unit '$u' — try: mac list"
    done
    for id in "${ORDERED[@]}"; do
        for u in "$@"; do
            if [[ "$u" == *:* ]]; then
                if [[ "$id" == ${~u} ]]; then SELECTED+=("$id"); break; fi
            elif [[ "${R_UNIT[$id]}" == "$u" ]]; then
                SELECTED+=("$id"); break
            fi
        done
    done
    (( ${#SELECTED} )) || die "nothing matched: $*"
}

_evaluate_one() {
    local id=$1 rc
    REASON=''
    provider_call check "$id"; rc=$?
    case $rc in
        0) ST[$id]=ok ;;
        1) ST[$id]=drift ;;
        *) ST[$id]=unknown ;;
    esac
    RSN[$id]="$REASON"
    journal "check $id ${ST[$id]} ${RSN[$id]}"
}

evaluate() {
    local id
    ST=(); RSN=(); SKIP=()
    for id in "${SELECTED[@]}"; do
        cancelled && return
        _evaluate_one "$id"
    done
}

os_banner() {
    local now last
    now=$(os_build_now); last=$(os_build_last)
    [[ -z "$last" || "$now" == "$last" ]] && return
    print -r -- ""
    print -r -- "  $S_WARN ${C_BOLD}$(os_name) (build $last → $now) since your last sync${C_RESET}"
    dim  "    system updates commonly reset defaults and revoke permissions"
}

row() { printf '    %-9s %-40s %s\n' "$1" "$2" "$3" }

# Steps nothing here can take. Printed in dependency order at the end of every
# run, so what is blocking comes before what merely follows it.
render_manual() {
    local id
    local -a pending
    for id in "${SELECTED[@]}"; do
        [[ "${R_PROVIDER[$id]}" == manual ]] || continue
        [[ "${ST[$id]}" == ok ]] && continue
        pending+=("$id")
    done
    (( ${#pending} )) || return 0
    hdr "by hand (${#pending})"
    for id in "${pending[@]}"; do
        print -r -- "    ${C_BOLD}$(target_of "$id")${C_RESET}"
        print -r -- "      ${RSN[$id]}"
    done
}

render_plan() {
    local id n_ok=0
    local -a drift unknown manual_ids
    for id in "${SELECTED[@]}"; do
        case "${ST[$id]}" in
            ok)      (( n_ok++ )) ;;
            drift)   [[ "${R_PROVIDER[$id]}" == manual ]] && manual_ids+=("$id") || drift+=("$id") ;;
            unknown) unknown+=("$id") ;;
        esac
    done
    if (( ${#drift} )); then
        hdr "drift (${#drift})"
        for id in "${drift[@]}"; do row "${R_PROVIDER[$id]}" "$(target_of "$id")" "${RSN[$id]}"; done
    fi
    if (( ${#unknown} )); then
        hdr "unknown (${#unknown})"
        for id in "${unknown[@]}"; do row "${R_PROVIDER[$id]}" "$(target_of "$id")" "${RSN[$id]}"; done
    fi
    typeset -gi PLAN_CHANGES=$(( ${#drift} + ${#unknown} ))
    typeset -gi PLAN_DRIFT=${#drift}
    typeset -gi PLAN_UNKNOWN=${#unknown}
    typeset -gi PLAN_OK=$n_ok
    typeset -gi PLAN_MANUAL=${#manual_ids}
}

# The plan is a snapshot taken before anything ran, so a resource fed by one
# applied earlier in the same pass was judged against reality that no longer
# holds — it would sit at "ok" while its input changed underneath it, and only
# a second sync would notice. Applying something re-checks whatever follows it.
# Asking for the password is the engine's job, not a chore to hand back to the
# person running it. Done once, up front, so a long sync cannot stall on a
# prompt halfway through — and only when the plan actually contains something
# root must write.
_plan_wants_root() {
    local id
    for id in "${SELECTED[@]}"; do
        [[ "${ST[$id]}" == drift ]] || continue
        [[ "${R_PROVIDER[$id]}" == manual ]] && continue
        parse_args "$id"
        [[ -n "${P[root]:-}" ]] && return 0
    done
    return 1
}

# A `run` with no check, or check=always, is a deliberate "just do it" escape
# hatch — it has no notion of being satisfied, so re-checking it would report
# failure every single time. Everything else can and must be verified.
_verifiable() {
    local id=$1
    [[ "${R_PROVIDER[$id]}" == manual ]] && return 1
    if [[ "${R_PROVIDER[$id]}" == run ]]; then
        parse_args "$id"
        [[ -z "${P[check]:-}" || "${P[check]}" == always ]] && return 1
    fi
    return 0
}

sudo_ensure() {
    sudo -n true 2>/dev/null && return 0
    print -r -- ""
    print -r -- "  ${C_BOLD}Some of this needs your password.${C_RESET}"
    dim  "    Writing to /etc and /Library, and loading a system daemon."
    print -r -- ""
    sudo -v || return 1
    print -r -- ""
    return 0
}

apply_all() {
    local id t label
    typeset -A DIRTY
    if _plan_wants_root && ! sudo_ensure; then
        # For sync, refusing to start beats a half-converged machine. For the
        # workspace commands it is the opposite: they exist to get the desktop
        # into a usable state, and most of what they do needs no password at all.
        if (( ROOT_OPTIONAL )); then
            print -r -- "  $S_WARN no password — the parts that need root are skipped"
            print -r -- ""
        else
            print -r -- "  $S_BAD no password given — nothing was applied"
            return 1
        fi
    fi
    for id in "${SELECTED[@]}"; do
        cancelled && break
        if [[ -n "${DIRTY[$id]:-}" && "${ST[$id]}" != drift ]]; then
            _evaluate_one "$id"
        fi
        [[ "${ST[$id]}" == drift ]] || continue
        [[ "${R_PROVIDER[$id]}" == manual ]] && continue
        if [[ -n "${SKIP[$id]:-}" ]]; then
            ST[$id]=skipped; RSN[$id]="requires ${SKIP[$id]}"
            journal "skip $id (${SKIP[$id]})"
            continue
        fi
        REASON=''; LAST_OUTPUT=''
        label="${R_PROVIDER[$id]} $(target_of "$id")"
        spin_start "$label"
        if provider_apply "$id"; then
            # An exit code of 0 is a claim, not a result. Re-checking is the only
            # thing standing between "it worked" and "it said it worked" — every
            # provider already knows how to tell whether reality matches.
            if _verifiable "$id"; then
                REASON=''
                if ! provider_call check "$id"; then
                    ST[$id]=failed
                    RSN[$id]="applied, but still not satisfied: ${REASON:-unchanged}"
                    spin_stop
                    print -r -- "  $S_BAD ${C_BOLD}$label${C_RESET} — ${RSN[$id]}"
                    undo_rollback
                    journal "verify $id FAILED ${RSN[$id]}"
                    propagate_skip "$id" "$id"
                    continue
                fi
            fi
            undo_commit
            ST[$id]=changed
            for t in ${=E_ORDER[$id]:-}; do DIRTY[$t]=1; done
            spin_stop
            print -r -- "  $S_OK $label"
            journal "apply $id ok"
        else
            spin_stop
            if cancelled; then
                ST[$id]=cancelled
                print -r -- "  ${C_YEL}^C${C_RESET} $label ${C_DIM}— interrupted${C_RESET}"
                undo_rollback
                journal "cancel $id"
                break
            fi
            ST[$id]=failed
            RSN[$id]="${REASON:-apply failed}"
            print -r -- "  $S_BAD ${C_BOLD}$label${C_RESET} — ${RSN[$id]}"
            undo_rollback
            journal "apply $id FAILED ${RSN[$id]}"
            propagate_skip "$id" "$id"
        fi
    done
    spin_stop
}

render_result() {
    local id root
    local -i n_changed=0 n_failed=0 n_skipped=0 n_ok=0 n_cancelled=0
    for id in "${SELECTED[@]}"; do
        case "${ST[$id]}" in
            changed)   (( n_changed++ )) ;;
            failed)    (( n_failed++ )) ;;
            skipped)   (( n_skipped++ )) ;;
            cancelled) (( n_cancelled++ )) ;;
            ok|*)      (( n_ok++ )) ;;
        esac
    done
    if (( n_skipped )); then
        print -r -- ""
        for id in "${SELECTED[@]}"; do
            [[ "${ST[$id]}" == skipped ]] || continue
            root=${SKIP[$id]}
            print -r -- "    $S_SKIP $(target_of "$id") ${C_DIM}— skipped, requires $(target_of "$root")${C_RESET}"
        done
    fi
    render_manual
    print -r -- ""
    if cancelled; then
        print -r -- "  ${C_YEL}cancelled${C_RESET} · $n_changed changed before it stopped · nothing left half-written"
        return 130
    fi
    print -r -- "  $n_changed changed · $n_ok unchanged · $n_failed failed · $n_skipped skipped"
    if (( n_failed )); then
        local -A roots
        for id in "${SELECTED[@]}"; do
            [[ "${ST[$id]}" == failed ]] && roots[$id]=1
        done
        print -r -- "  ${C_DIM}root cause: ${(k)roots} — journal: ${JOURNAL:t}${C_RESET}"
    fi
    (( n_failed )) && return 2
    return 0
}

cmd_check() {
    build_graph; topo; select_ids "$@"
    os_banner
    spin_start "checking ${#SELECTED} resources"
    evaluate
    spin_stop
    render_plan
    render_manual
    if (( PLAN_CHANGES == 0 )); then
        print -r -- ""
        print -r -- "  $S_OK $PLAN_OK converged$( (( PLAN_MANUAL )) && print -n " · $PLAN_MANUAL for you to do")"
        return 0
    fi
    print -r -- ""
    local summary=""
    (( PLAN_DRIFT ))   && summary="$PLAN_DRIFT change(s)"
    (( PLAN_UNKNOWN )) && summary="${summary:+$summary · }$PLAN_UNKNOWN unknown"
    print -r -- "  $summary · run ${C_BOLD}mac sync${C_RESET} to apply"
    return 1
}

cmd_sync() {
    lock_acquire
    journal_open sync "$@"
    build_graph; topo; select_ids "$@"
    os_banner
    spin_start "checking ${#SELECTED} resources"
    evaluate
    spin_stop
    render_plan
    if (( PLAN_CHANGES == 0 )); then
        render_manual
        print -r -- ""
        print -r -- "  $S_OK $PLAN_OK converged — nothing to do"
        os_build_record
        return 0
    fi
    print -r -- ""
    apply_all
    os_build_record
    local rc=0
    render_result || rc=$?
    return $rc
}

cmd_tree() {
    build_graph; topo
    local u dep id
    local -a seen
    for id in "${ORDERED[@]}"; do
        (( ${seen[(Ie)${R_UNIT[$id]}]} )) || seen+=("${R_UNIT[$id]}")
    done
    for u in "${seen[@]}"; do
        local deps="${U_REQ[$u]:-}"
        print -r -- "  ${C_BOLD}$u${C_RESET}${deps:+ ${C_DIM}← $deps${C_RESET}}"
        for id in $(ids_of_unit "$u"); do
            print -r -- "      ${C_DIM}${R_PROVIDER[$id]}${C_RESET} $(target_of "$id")"
        done
    done
}

cmd_list() {
    local u
    print -r -- "  ${C_BOLD}units${C_RESET}"
    for u in "${U_NAMES[@]}"; do
        printf '    %-14s %d resources%s%s\n' "$u" "$(ids_of_unit "$u" | wc -l | tr -d ' ')" \
            "${U_WORKSPACE[$u]:+  ${C_DIM}[workspace]${C_RESET}}" \
            "${U_REQ[$u]:+  ← ${U_REQ[$u]}}"
    done
}

# `mac log` alone is the last run. Everything else is for the case where the
# interesting run was not the last one.
cmd_log() {
    local -a logs
    logs=("$STATE"/journal/*.log(Nom))
    (( ${#logs} )) || { print -r -- "  no runs recorded yet"; return 0 }

    case "${1:-}" in
        -l|--list)
            print -r -- ""
            local f head
            for f in "${logs[@]:0:${2:-20}}"; do
                head=$(sed -n '1s/^# //p' "$f")
                printf '    %-28s %s\n' "${f:t:r}" "${head%% @ *}"
            done
            print -r -- ""
            dim  "    mac log <name>   one of these in full"
            print -r -- ""
            ;;
        -f|--follow) tail -f "${logs[1]}" ;;
        '')          cat "${logs[1]}" ;;
        *)
            local want="$STATE/journal/${1%.log}.log"
            [[ -f "$want" ]] || die "no such run: $1  (mac log -l lists them)"
            cat "$want"
            ;;
    esac
}

# The desktop: everything that has to be running, and every preference that only
# makes sense while it is. Nothing here starts at login, so `up` is what makes the
# machine usable after a reboot and `down` is what makes it usable without one.
#
# Which units those are is declared by the units themselves — a unit that sets
# workspace=1 is part of the desktop. Keeping the list in the engine meant every
# new unit needed a second edit somewhere else, and forgetting it was silent.
#
# Builds are deliberately out of scope. `up` starts what is installed and says so
# when something is missing; making a stale binary current is `mac sync`'s job,
# and a workspace command should never turn into a ten-minute compile.
# A whole unit, or a single resource inside one that is otherwise sync's
# business — the ainto unit builds an app (sync) and sets one hotkey (workspace),
# and only the second belongs to the desktop.
workspace_selectors() {
    local u id
    for u in "${U_NAMES[@]}"; do
        [[ -n "${U_WORKSPACE[$u]:-}" ]] && print -r -- "$u"
    done
    for id in "${R_IDS[@]}"; do
        [[ -n "${U_WORKSPACE[${R_UNIT[$id]}]:-}" ]] && continue
        parse_args "$id"
        [[ -n "${P[workspace]:-}" ]] && print -r -- "$id"
    done
    return 0
}

cmd_workspace() {
    local action=${1:-}
    case "$action" in
        up)     _workspace_up ;;
        down)   _workspace_down ;;
        reload) _workspace_down; print -r -- ""; cancelled || _workspace_up ;;
        *)      print -ru2 -- "usage: mac workspace <up|down|reload>"; return 2 ;;
    esac
}

_workspace_up() {
    hdr "workspace up"
    ROOT_OPTIONAL=1
    local -a sel; sel=(${(f)"$(workspace_selectors)"})
    cmd_sync "${sel[@]}"
}

# Reverse topological order: stop the things that depend on something before the
# something. Unlike a failed apply, this is a state the machine is expected to
# come back from, so nothing is forgotten and nothing is uninstalled.
_workspace_down() {
    lock_acquire
    journal_open workspace down
    build_graph; topo
    local -a sel; sel=(${(f)"$(workspace_selectors)"})
    select_ids "${sel[@]}"
    hdr "workspace down"
    local -a targets
    local id rc=0 n=0
    targets=("${(@Oa)SELECTED}")
    # Unlike sync, a missing password does not abort. Everything that can be
    # handed back still is: stopping halfway leaves the machine in exactly the
    # state this command exists to get out of.
    if _selection_wants_root && ! sudo_ensure; then
        print -r -- "  $S_WARN no password — the parts that need root are skipped"
        print -r -- ""
    fi
    for id in "${targets[@]}"; do
        cancelled && break
        case "${R_PROVIDER[$id]}" in
            manual|link|file|build|daemon|software) continue ;;
        esac
        REASON=''
        spin_start "${R_PROVIDER[$id]} $(target_of "$id")"
        if provider_call revert "$id"; then
            (( n++ ))
            spin_stop
            print -r -- "  $S_OK ${R_PROVIDER[$id]} $(target_of "$id")"
            journal "down $id ok"
        else
            rc=1
            spin_stop
            print -r -- "  $S_BAD ${R_PROVIDER[$id]} $(target_of "$id") — ${REASON:-failed}"
            journal "down $id FAILED ${REASON}"
        fi
    done
    spin_stop
    _workspace_restart_owners
    print -r -- ""
    if cancelled; then
        print -r -- "  ${C_YEL}cancelled${C_RESET} · $n handed back before it stopped"
        return 130
    fi
    print -r -- "  $n down · $( (( rc )) && print "some failed" || print "no failures")"
    return $rc
}

# A defaults write is only visible once the app that caches it is restarted, and
# `down` has just stopped most of them — the Dock is the one that must come back.
_workspace_restart_owners() {
    local app
    for app in "$STATE"/pending-restart/*(N); do
        [[ "${app:t}" == Dock ]] || continue
        killall Dock 2>/dev/null && restart_done Dock
    done
}

_selection_wants_root() {
    local id
    for id in "${SELECTED[@]}"; do
        parse_args "$id"
        [[ -n "${P[root]:-}" ]] && return 0
    done
    return 1
}

# The guardrails that keep units from decaying back into shell scripts, and keep
# every write reversible. Both are things a person will forget and a machine
# will not.
cmd_lint() {
    local f line n rc=0 id
    local forbidden='^[[:space:]]*(defaults|pkill|killall|rm|curl|open|ditto|codesign|sudo|launchctl|mv|cp|ln|mkdir|installer|hdiutil|xattr|osascript|git|brew)[[:space:]]'
    for f in "$ROOT"/units/*.zsh(N) "$ROOT"/private/*/units/*.zsh(N); do
        n=0
        while IFS= read -r line; do
            (( n++ ))
            [[ "$line" == [[:space:]]#\#* ]] && continue
            if [[ "$line" =~ $forbidden ]]; then
                print -r -- "  $S_BAD ${f:t}:$n imperative command in a unit — move it into recipes/"
                dim "      $line"
                rc=1
            fi
        done < "$f"
    done

    local -a undocumented no_undo no_down no_provider
    for id in "${R_IDS[@]}"; do
        parse_args "$id"
        case "${R_PROVIDER[$id]}" in
            run)
                [[ -n "${P[why]:-}" ]] || undocumented+=("$id")
                [[ -n "${P[revert]:-}" || -n "${P[irreversible]:-}" ]] || no_undo+=("$id")
                ;;
            default)
                [[ -n "${P[on_workspace_down]:-}" ]] || no_down+=("$id")
                ;;
        esac
        (( ${+functions[${R_PROVIDER[$id]}_undo]} )) || no_provider+=("$id")
    done
    for id in "${undocumented[@]}"; do
        print -r -- "  $S_BAD $id — every run= escape hatch needs a why="; rc=1
    done
    for id in "${no_undo[@]}"; do
        print -r -- "  $S_BAD $id — needs revert= (how to take it back) or irreversible=<why not>"; rc=1
    done
    for id in "${no_down[@]}"; do
        print -r -- "  $S_BAD $id — every default needs on_workspace_down= (a value, or 'delete')"; rc=1
    done
    for id in "${no_provider[@]}"; do
        print -r -- "  $S_BAD $id — provider '${R_PROVIDER[$id]}' has no _undo and may not write"; rc=1
    done

    local -i escapes=0
    for id in "${R_IDS[@]}"; do [[ "${R_PROVIDER[$id]}" == run ]] && (( escapes++ )); done
    (( rc == 0 )) && print -r -- "$S_OK units are declarations only · every write reversible · ${escapes} run escape hatches, all documented"
    return $rc
}

# Tasks are one-shot scripts, discovered rather than hardcoded, so a tree
# added under private/ brings its own without the core knowing about it.
# Only tasks/ at the root. A private tree owns a command of its own name, so
# its tasks are reached as `mac vpn status`, never as `mac do status` — pulling
# them in here made every tree's commands collide in one flat namespace.
_task_file() {
    local f
    for f in "$ROOT"/tasks/$1.zsh(N); do
        print -r -- "$f"; return 0
    done
    return 1
}

cmd_do() {
    local name=${1:-} f
    if [[ -n "$name" ]] && f=$(_task_file "$name"); then
        shift
        ( cd "$ROOT" && zsh "$f" "$@" )
        return $?
    fi
    [[ -n "$name" ]] && print -r -- "  $S_BAD no such task: $name"
    print -r -- ""
    print -r -- "  tasks"
    for f in "$ROOT"/tasks/*.zsh(N); do
        printf '    %-14s %s\n' "${f:t:r}" "$(sed -n '2s/^# *//p' "$f")"
    done
    print -r -- ""
    return 1
}

# A tree under private/ owns a command of its own name, so `mac vpn uri` runs
# private/vpn/tasks/uri.zsh. Core dispatches by tree, and stays ignorant of
# what any given tree is for.
cmd_private() {
    local tree=$1; shift
    local name=${1:-} f
    if [[ -n "$name" && -f "$ROOT/private/$tree/tasks/$name.zsh" ]]; then
        shift
        ( cd "$ROOT" && zsh "$ROOT/private/$tree/tasks/$name.zsh" "$@" )
        return $?
    fi
    [[ -n "$name" ]] && print -r -- "  $S_BAD no such $tree command: $name"
    print -r -- ""
    print -r -- "  ${C_BOLD}mac $tree${C_RESET}"
    for f in "$ROOT/private/$tree"/tasks/*.zsh(N); do
        printf '    %-10s %s\n' "${f:t:r}" "$(sed -n '2s/^# *//p' "$f")"
    done
    print -r -- ""
    dim "    mac check $tree · mac sync $tree   the declaration itself"
    print -r -- ""
    return 1
}
