# An app is stopped only when something it would overwrite is actually being
# written this run — otherwise sync would kill your apps for no reason.
stop_check() {
    local app=${POS[1]} guard="${P[before]:-}" t
    pgrep -qx "$app" || return 0
    if [[ -z "$guard" ]]; then REASON="running"; return 1; fi
    for t in "${SELECTED[@]}"; do
        [[ "$t" == ${~guard} ]] || continue
        if [[ "${ST[$t]:-}" == drift ]]; then
            REASON="stop before writing $(target_of "$t")"
            return 1
        fi
    done
    return 0
}

stop_apply() {
    local app=${POS[1]}
    _svc_stop "$app" || { REASON="$app will not exit"; return 1 }
    needs_restart "$app"
    return 0
}

stop_revert() { return 0 }

stop_describe() { print -r -- "${POS[1]}" }
