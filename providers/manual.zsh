# Never applies anything. It only ever reports, because a human has to do it.
manual_check() {
    local detect="${P[detect]:-}"
    if [[ -n "$detect" ]] && ( eval "$detect" ) >/dev/null 2>&1; then return 0; fi
    [[ -f "$STATE/ack/${POS[1]}" ]] && return 0
    REASON="${P[do]:-${POS[1]}}"
    return 1
}

manual_revert() { return 0 }

manual_describe() { print -r -- "${POS[1]}" }
