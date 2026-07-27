typeset -gA ST RSN SKIP
typeset -ga SELECTED
typeset -g REASON='' LAST_OUTPUT=''
typeset -gi VERBOSE=0 ASSUME_YES=0

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

# Two passes: a stop resource asks whether the things it guards are in drift,
# so it can only be judged once everything else has been.
evaluate() {
    local id
    ST=(); RSN=(); SKIP=()
    for id in "${SELECTED[@]}"; do
        [[ "${R_PROVIDER[$id]}" == stop ]] && continue
        _evaluate_one "$id"
    done
    for id in "${SELECTED[@]}"; do
        [[ "${R_PROVIDER[$id]}" == stop ]] || continue
        _evaluate_one "$id"
    done
}

# "Declared and then removed" and "declared somewhere we cannot read" look
# identical from the ledger: the unit file simply is not there. An uninitialised
# submodule would therefore present a working setup as garbage to revert, so
# while any tree is missing we decline to nominate anything at all.
trees_incomplete() {
    [[ -f "$ROOT/.gitmodules" ]] || return 1
    local line sub
    for line in ${(f)"$(git -C "$ROOT" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null)"}; do
        sub="${line#* }"
        [[ -n "$sub" && -d "$ROOT/$sub" ]] || continue
        [[ -z "$(print -rl -- "$ROOT/$sub"/*(DN))" ]] && return 0
    done
    return 1
}

pending_reverts() {
    trees_incomplete && return 0
    local id
    for id in "${(@k)L_OWNED}"; do
        [[ -n "${R_PROVIDER[$id]:-}" ]] || print -r -- "$id"
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

render_plan() {
    local id n_ok=0 n_drift=0 n_unknown=0
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
    if (( ${#manual_ids} )); then
        hdr "needs you (${#manual_ids})"
        for id in "${manual_ids[@]}"; do row "${R_PROVIDER[$id]}" "$(target_of "$id")" "${RSN[$id]}"; done
    fi
    local -a revs; revs=($(pending_reverts))
    if (( ${#revs} )); then
        hdr "pending revert (${#revs})${C_RESET}${C_DIM} — run: mac prune${C_RESET}"
        for id in "${revs[@]}"; do row "${id%%:*}" "$(target_of "$id")" "no longer declared"; done
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
    local id t
    typeset -A DIRTY
    if _plan_wants_root && ! sudo_ensure; then
        print -r -- "  $S_BAD no password given — nothing was applied"
        return 1
    fi
    for id in "${SELECTED[@]}"; do
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
        print -r -- "  ${C_DIM}…${C_RESET} ${R_PROVIDER[$id]} $(target_of "$id")"
        if provider_call apply "$id"; then
            # An exit code of 0 is a claim, not a result. Re-checking is the only
            # thing standing between "it worked" and "it said it worked" — every
            # provider already knows how to tell whether reality matches.
            if _verifiable "$id"; then
                REASON=''
                if ! provider_call check "$id"; then
                    ST[$id]=failed
                    RSN[$id]="applied, but still not satisfied: ${REASON:-unchanged}"
                    journal "verify $id FAILED ${RSN[$id]}"
                    propagate_skip "$id" "$id"
                    continue
                fi
            fi
            ST[$id]=changed
            ledger_claim "$id"
            for t in ${=E_ORDER[$id]:-}; do DIRTY[$t]=1; done
            journal "apply $id ok"
        else
            ST[$id]=failed
            RSN[$id]="${REASON:-apply failed}"
            journal "apply $id FAILED ${RSN[$id]}"
            [[ -n "$LAST_OUTPUT" ]] && journal "$LAST_OUTPUT"
            propagate_skip "$id" "$id"
        fi
    done
}

render_result() {
    local id root
    local -i n_changed=0 n_failed=0 n_skipped=0 n_ok=0
    local -a units_seen
    print -r -- ""
    for id in "${SELECTED[@]}"; do
        case "${ST[$id]}" in
            changed) (( n_changed++ )); print -r -- "  $S_OK ${R_PROVIDER[$id]} $(target_of "$id")" ;;
            failed)  (( n_failed++ ));  print -r -- "  $S_BAD ${C_BOLD}${R_PROVIDER[$id]} $(target_of "$id")${C_RESET} — ${RSN[$id]}" ;;
            skipped) (( n_skipped++ )) ;;
            ok|*)    (( n_ok++ )) ;;
        esac
    done
    if (( n_skipped )); then
        for id in "${SELECTED[@]}"; do
            [[ "${ST[$id]}" == skipped ]] || continue
            root=${SKIP[$id]}
            print -r -- "    $S_SKIP $(target_of "$id") ${C_DIM}— skipped, requires $(target_of "$root")${C_RESET}"
        done
    fi
    print -r -- ""
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
    evaluate
    render_plan
    if (( PLAN_CHANGES == 0 )); then
        print -r -- "$S_OK $PLAN_OK resources converged$( (( PLAN_MANUAL )) && print -n " · $PLAN_MANUAL need you")"
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
    trap 'lock_release' EXIT INT TERM
    journal_open sync "$@"
    build_graph; topo; select_ids "$@"
    os_banner
    evaluate
    render_plan
    if (( PLAN_CHANGES == 0 )); then
        print -r -- "$S_OK $PLAN_OK resources converged — nothing to do"
        os_build_record
        return 0
    fi
    print -r -- ""
    apply_all
    ledger_save
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
        printf '    %-14s %d resources%s\n' "$u" "$(ids_of_unit "$u" | wc -l | tr -d ' ')" \
            "${U_REQ[$u]:+  ← ${U_REQ[$u]}}"
    done
}

cmd_explain() {
    local want=$1 id
    [[ -n "$want" ]] || die "usage: mac explain <resource>"
    build_graph; topo
    for id in "${R_IDS[@]}"; do
        [[ "$id" == *"$want"* ]] || continue
        print -r -- "  ${C_BOLD}$id${C_RESET}"
        print -r -- "    unit      ${R_UNIT[$id]}"
        print -r -- "    provider  ${R_PROVIDER[$id]}"
        print -r -- "    args      ${R_ARGS[$id]}"
        print -r -- "    owned     $(ledger_owned "$id" && print yes || print no)"
        before_exists "$id" && print -r -- "    before    $(before_get "$id")"
        [[ -n "${E_DEP[$id]:-}" ]] && print -r -- "    blocks    ${E_DEP[$id]}"
        REASON=''; provider_call check "$id"
        print -r -- "    state     $? ${REASON}"
    done
}

# A resource that vanished from the repo still has to be revertible, so
# revert must work from the id plus the stored before-image alone.
resurrect() {
    local id=$1
    local -a f; f=("${(@ps:\t:)L_OWNED[$id]}")
    R_PROVIDER[$id]=${f[1]}
    R_UNIT[$id]=${f[2]:-gone}
    R_ORDER[$id]=$(( ++REG_N ))
    typeset -ga "R_ARGV_$REG_N"; set -A "R_ARGV_$REG_N"
}

cmd_prune() {
    lock_acquire
    trap 'lock_release' EXIT INT TERM
    journal_open prune
    build_graph; topo
    local -a revs; revs=($(pending_reverts))
    if trees_incomplete; then
        print -r -- "  $S_WARN a submodule is not checked out — refusing to revert anything"
        dim  "    run: git submodule update --init --recursive"
        return 1
    fi
    if (( ${#revs} == 0 )); then print -r -- "$S_OK nothing to revert"; return 0; fi
    local id rc=0
    for id in "${revs[@]}"; do
        resurrect "$id"
        REASON=''
        if provider_call revert "$id"; then
            ledger_release "$id"; before_drop "$id"
            print -r -- "  $S_OK reverted $id"
            journal "revert $id ok"
        else
            rc=1
            print -r -- "  $S_BAD $id — ${REASON:-revert failed}"
            print -r -- "    ${C_DIM}drop it from the ledger with: mac forget $id${C_RESET}"
            journal "revert $id FAILED ${REASON}"
        fi
    done
    ledger_save
    return $rc
}

cmd_ack() {
    local name=$1
    [[ -n "$name" ]] || die "usage: mac ack <manual-step>"
    mkdir -p "$STATE/ack"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$STATE/ack/$name"
    print -r -- "$S_OK acknowledged '$name' — it will stop being reported"
}

cmd_forget() {
    local id=$1
    [[ -n "$id" ]] || die "usage: mac forget <resource-id>"
    ledger_owned "$id" || die "not owned by mac_setup: $id"
    ledger_release "$id"; before_drop "$id"; ledger_save
    print -r -- "$S_OK forgot $id (machine untouched)"
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

_app_up() {
    local name=$1 url tag out sha stage staged team ver fmt kind pinned
    if [[ -n "${P[github]:-}" ]]; then
        out=$(gh_latest "${P[github]}" "${P[asset]:-}") || {
            print -r -- "  $S_WARN $name — GitHub API unavailable (rate limit?), leaving apps.lock alone"; return 1 }
        tag=${out%%$'\t'*}; url=${out#*$'\t'}
    elif [[ -n "${P[url]:-}" ]]; then
        url="${P[url]}"; tag="${P[version]:-pinned}"
    else
        print -r -- "  $S_BAD $name — needs url= or github="; return 1
    fi
    if [[ "$url" == "$(lock_get "$name" url)" ]]; then
        print -r -- "  $S_OK $name already at $tag"; return 0
    fi
    print -r -- "  ${C_DIM}…${C_RESET} $name → $tag"
    local file; file=$(_app_fetch "$url" "") || { print -r -- "  $S_BAD $name — $REASON"; return 1 }
    sha=$(shasum -a 256 "$file" | cut -d' ' -f1)
    fmt=$(_app_format)
    stage="$STATE/cache/up-$name"
    kind=$(_app_stage "$file" "$stage" "$fmt") || { print -r -- "  $S_BAD $name — $REASON"; return 1 }
    if [[ "$kind" != pkg ]]; then
        staged=$(find "$stage" -maxdepth 2 -name '*.app' -print -quit)
        team=$(_app_teamid "$staged"); ver=$(_app_version "$staged")
        pinned=$(lock_get "$name" teamid)
        if [[ -n "$pinned" && -n "$team" && "$pinned" != "$team" ]]; then
            print -r -- "  $S_BAD $name — publisher changed ($pinned → $team); refusing"
            rm -rf "$stage"; return 1
        fi
        if [[ -z "$team" && "${P[trust]:-}" != unverified ]]; then
            print -r -- "  $S_WARN $name is unsigned (no Team ID) — pinned by sha256 only"
        fi
    fi
    rm -rf "$stage"
    lock_set "$name" "version=$tag" "url=$url" "sha256=$sha" ${team:+"teamid=$team"} ${ver:+"upstream_version=$ver"}
    print -r -- "  $S_OK $name $tag recorded in apps.lock — review the diff, then: mac sync"
}

cmd_up() {
    lock_acquire
    trap 'lock_release' EXIT INT TERM
    journal_open up "$@"
    build_graph; topo
    local -a targets
    local id name rc=0
    for id in "${ORDERED[@]}"; do
        [[ "${R_PROVIDER[$id]}" == app ]] || continue
        name=${id#app:}
        (( $# )) && [[ " $* " != *" $name "* ]] && continue
        targets+=("$id")
    done
    (( ${#targets} )) || die "no external apps declared${1:+ matching '$*'}"
    for id in "${targets[@]}"; do
        parse_args "$id"
        _app_up "${id#app:}" || rc=1
    done
    return $rc
}

# Bring the desktop up, then re-read the configs of what is now running.
# Nothing starts at login, so this is the command that makes the machine
# usable after a reboot.
cmd_reload() {
    cmd_sync activate
    local rc=$?
    print -r -- ""
    zsh "$ROOT/recipes/reload.zsh"
    return $rc
}

cmd_restart() { cmd_sync activate }

# Everything in /Applications that no resource claims. The two ways state leaks
# onto the machine — apps and defaults — are both instrumented, so the repo
# cannot silently fall behind.
_scan_key() { local k="${1//[[:space:]]/}"; k="${k%.app}"; k="${k:l}"; print -r -- "${k//[^a-z0-9]/}" }

cmd_scan() {
    build_graph; topo
    local -A managed
    local id name entry p
    for id in "${R_IDS[@]}"; do
        parse_args "$id"
        case "${R_PROVIDER[$id]}" in
            app)   p=$(lock_get "${id#app:}" path); [[ -n "$p" ]] && managed[$(_scan_key "${p:t}")]=1 ;;
            build) managed[$(_scan_key "${${P[app]}:t}")]=1 ;;
        esac
    done
    for name in ${(f)"$(python3 "$ROOT/engine/cask_apps.py" 2>/dev/null)"}; do
        [[ -n "$name" ]] && managed[$name]=1
    done
    local -A ignored
    if [[ -f "$ROOT/apps/ignore.txt" ]]; then
        while read -r entry; do
            entry=${entry%%\#*}
            entry=$(_scan_key "$entry")
            [[ -n "$entry" ]] && ignored[$entry]=1
        done < "$ROOT/apps/ignore.txt"
    fi
    local -a unknown
    for p in /Applications/*.app(N); do
        name=${p:t}
        entry=$(_scan_key "$name")
        [[ -n "${managed[$entry]:-}" || -n "${ignored[$entry]:-}" ]] && continue
        unknown+=("$name")
    done
    if (( ${#unknown} == 0 )); then
        print -r -- "$S_OK every app in /Applications is declared or ignored"
        return 0
    fi
    hdr "unmanaged in /Applications (${#unknown})"
    for name in "${unknown[@]}"; do
        printf '    %-34s %-30s %s\n' "$name" \
            "$(defaults read "/Applications/$name/Contents/Info" CFBundleIdentifier 2>/dev/null)" \
            "→ mac adopt ${name%.app}"
    done
    print -r -- ""
    dim "    to leave one out for good, add it to apps/ignore.txt"
    return 1
}

cmd_adopt() {
    local want=$1 dest bundle ver team cask
    [[ -n "$want" ]] || die "usage: mac adopt <App>"
    dest="/Applications/${want%.app}.app"
    [[ -d "$dest" ]] || die "not found: $dest"
    bundle=$(defaults read "$dest/Contents/Info" CFBundleIdentifier 2>/dev/null)
    ver=$(defaults read "$dest/Contents/Info" CFBundleShortVersionString 2>/dev/null)
    team=$(codesign -dv --verbose=4 "$dest" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')
    # anchored: brew only honours regex inside slashes, and a fuzzy match would
    # suggest a completely different app (structured -> structuredlogviewer)
    cask=$(brew search --cask "/^${${want%.app}:l}\$/" 2>/dev/null | grep -v '^==>' | head -1)
    print -r -- "  ${C_BOLD}${want%.app}${C_RESET}  $ver  ${C_DIM}$bundle${C_RESET}"
    print -r -- ""
    if [[ -n "$cask" ]]; then
        print -r -- "  Homebrew has a cask — declare it in the Brewfile:"
        print -r -- "      ${C_BOLD}cask \"$cask\"${C_RESET}"
    else
        print -r -- "  No cask upstream — add to units/apps.zsh:"
        print -r -- "      ${C_BOLD}app ${${want%.app}:l} url='<download url>'${C_RESET}"
        [[ "$team" == "not set" || -z "$team" ]] \
            && dim "      (unsigned publisher — it will be pinned by sha256)" \
            || dim "      (Team ID $team will be captured and enforced on updates)"
    fi
}

# Declaring a setting has to be easier than clicking it, or the repo rots.
cmd_capture() {
    local domain=$1 before after key type value
    [[ -n "$domain" ]] || die "usage: mac capture <domain>   (e.g. com.apple.dock)"
    before=$(mktemp); after=$(mktemp)
    defaults read "$domain" > "$before" 2>/dev/null
    print -r -- "  snapshot of ${C_BOLD}$domain${C_RESET} taken"
    print -r -- "  change the setting in System Settings, then press Enter"
    read -r _
    defaults read "$domain" > "$after" 2>/dev/null
    local -a keys
    keys=(${(f)"$(diff "$before" "$after" | grep '^>' | sed -E 's/^> *([A-Za-z0-9_.-]+) =.*/\1/' | sort -u)"})
    rm -f "$before" "$after"
    if (( ${#keys} == 0 )); then
        print -r -- "  ${C_DIM}nothing changed in $domain${C_RESET}"
        return 0
    fi
    hdr "add to the owning unit"
    for key in "${keys[@]}"; do
        [[ -n "$key" ]] || continue
        type=$(defaults read-type "$domain" "$key" 2>/dev/null | sed 's/^Type is //')
        value=$(defaults read "$domain" "$key" 2>/dev/null | tr '\n' ' ')
        case $type in
            boolean) type=bool; [[ "$value" == 1* ]] && value=true || value=false ;;
            integer) type=int ;;
            float)   type=float ;;
            *)       type=string ;;
        esac
        print -r -- "    default $domain $key $type ${value% }"
    done
}

# The one guardrail that keeps units from decaying back into shell scripts.
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
    local -a undocumented
    for id in "${R_IDS[@]}"; do
        [[ "${R_PROVIDER[$id]}" == run ]] || continue
        parse_args "$id"
        [[ -n "${P[why]:-}" ]] || undocumented+=("$id")
    done
    if (( ${#undocumented} )); then
        for id in "${undocumented[@]}"; do
            print -r -- "  $S_BAD $id — every run= escape hatch needs a why="
        done
        rc=1
    fi
    local -i escapes=0
    for id in "${R_IDS[@]}"; do [[ "${R_PROVIDER[$id]}" == run ]] && (( escapes++ )); done
    (( rc == 0 )) && print -r -- "$S_OK units are declarations only · ${escapes} run escape hatches, all documented"
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
