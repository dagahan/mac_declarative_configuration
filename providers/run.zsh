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

# An escape hatch still has to say how to take itself back. revert= is the
# inverse; irreversible= is the admission that there is none, and lint insists
# on one or the other so that "nothing can be undone" is never an accident.
run_undo() {
    local id=$1
    if [[ -n "${P[revert]:-}" ]]; then
        undo_push "${P[why]:-${id#run:}}" "cd ${(q)ROOT} && ${P[revert]}"
        return 0
    fi
    [[ -n "${P[irreversible]:-}" ]] && return 0
    REASON="no revert= and no irreversible= — refusing to run something that cannot be taken back"
    return 1
}

run_apply() {
    local cmd="${P[apply]:-}" rc=0
    [[ -n "$cmd" ]] || { REASON="no apply= given"; return 1 }
    stop_owner || return 1
    [[ "${P[sudo]:-0}" == 1 ]] && cmd="sudo $cmd"
    sh_run "cd ${(q)ROOT} && $cmd"; rc=$?
    (( rc == 0 )) && return 0
    REASON=$(sh_tail $rc)
    return 1
}

run_revert() {
    local rc=0
    [[ -n "${P[revert]:-}" ]] || { REASON="no revert declared"; return 1 }
    sh_run "cd ${(q)ROOT} && ${P[revert]}"; rc=$?
    (( rc == 0 )) && return 0
    REASON=$(sh_tail $rc)
    return 1
}

run_describe() { print -r -- "${P[why]:-${P[apply]:-}}" }
