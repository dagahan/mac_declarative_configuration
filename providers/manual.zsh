# Never applies anything. It only ever reports, because a human has to do it.
manual_check() {
    local detect="${P[detect]:-}" secs="${P[timeout]:-30}" rc
    if [[ -n "$detect" ]]; then
        with_timeout "$secs" "$detect" >/dev/null 2>&1; rc=$?
        (( rc == 0 )) && return 0
        [[ -f "$STATE/ack/${POS[1]}" ]] && return 0
        if (( rc == TIMED_OUT )); then
            REASON="gave up after ${secs}s asking whether this is done"
            return $TIMED_OUT
        fi
    fi
    [[ -f "$STATE/ack/${POS[1]}" ]] && return 0
    REASON="${P[do]:-${POS[1]}}"
    return 1
}

manual_revert() { return 0 }

manual_describe() { print -r -- "${POS[1]}" }
