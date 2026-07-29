run_check() {
    if [[ -z "${P[check]:-}" || "${P[check]}" == always ]]; then
        REASON="${P[why]:-always runs}"
        return 1
    fi
    local secs="${P[timeout]:-30}" rc
    with_timeout "$secs" "cd '$ROOT' && ${P[check]}" >/dev/null 2>&1; rc=$?
    (( rc == 0 )) && return 0
    if (( rc == TIMED_OUT )); then
        REASON="gave up after ${secs}s: ${P[check]}"
        return $TIMED_OUT
    fi
    REASON="not satisfied: ${P[check]}"
    return 1
}

run_apply() {
    local cmd="${P[apply]:-}" rc=0
    [[ -n "$cmd" ]] || { REASON="no apply= given"; return 1 }
    [[ "${P[sudo]:-0}" == 1 ]] && cmd="sudo $cmd"
    if (( VERBOSE )); then
        ( cd "$ROOT" && eval "$cmd" ); rc=$?
    else
        LAST_OUTPUT=$( cd "$ROOT" && eval "$cmd" 2>&1 ); rc=$?
    fi
    (( rc == 0 )) && return 0
    REASON=$(print -r -- "$LAST_OUTPUT" | grep -v '^[[:space:]]*$' | tail -2 | tr '\n' ' ')
    [[ -n "$REASON" ]] || REASON="exit $rc"
    return 1
}

run_revert() {
    local rc=0
    [[ -n "${P[revert]:-}" ]] || { REASON="no revert declared"; return 1 }
    LAST_OUTPUT=$( cd "$ROOT" && eval "${P[revert]}" 2>&1 ); rc=$?
    (( rc == 0 )) && return 0
    REASON=$(print -r -- "$LAST_OUTPUT" | grep -v '^[[:space:]]*$' | tail -2 | tr '\n' ' ')
    [[ -n "$REASON" ]] || REASON="exit $rc"
    return 1
}

run_describe() { print -r -- "${P[why]:-${P[apply]:-}}" }
