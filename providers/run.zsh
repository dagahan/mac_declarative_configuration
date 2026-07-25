run_check() {
    if [[ -z "${P[check]:-}" || "${P[check]}" == always ]]; then
        REASON="${P[why]:-always runs}"
        return 1
    fi
    if ( cd "$ROOT" && eval "${P[check]}" ) >/dev/null 2>&1; then return 0; fi
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
    [[ -n "${P[revert]:-}" ]] || { REASON="no revert declared"; return 1 }
    ( cd "$ROOT" && eval "${P[revert]}" )
}

run_describe() { print -r -- "${P[why]:-${P[apply]:-}}" }
