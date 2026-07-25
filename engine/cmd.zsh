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
    if (( $# == 0 )); then SELECTED=("${ORDERED[@]}"); return; fi
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

pending_reverts() {
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
    typeset -gi PLAN_OK=$n_ok
    typeset -gi PLAN_MANUAL=${#manual_ids}
}

apply_all() {
    local id
    for id in "${SELECTED[@]}"; do
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
            ST[$id]=changed
            ledger_claim "$id"
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
    print -r -- "  $PLAN_CHANGES change(s) · run ${C_BOLD}mac sync${C_RESET} to apply"
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

cmd_log() {
    local last
    last=$(ls -t "$STATE/journal"/*.log 2>/dev/null | head -1)
    [[ -n "$last" ]] || { print -r -- "no runs recorded yet"; return 0 }
    cat "$last"
}
