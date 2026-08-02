_svc_running() { pgrep -qx "$1" }

_svc_stop() {
    local app=$1 i
    _svc_running "$app" || return 0
    pkill -x "$app" 2>/dev/null
    for i in {1..50}; do
        _svc_running "$app" || break
        cancelled && return 1
        sleep 0.2
    done
    if _svc_running "$app"; then pkill -9 -x "$app" 2>/dev/null; sleep 0.5; fi
    _svc_running "$app" && return 1
    return 0
}

# Some apps keep their state in memory and flush it on quit, so a write made
# while they run is discarded the moment they exit. stop_app= says which one has
# to be down first. It used to be a provider of its own that inspected every
# other resource's state to work out whether it should act; as a property of the
# write it needs no such cross-talk, and the app is only ever stopped when that
# write is actually happening.
stop_owner() {
    local app="${P[stop_app]:-}"
    [[ -n "$app" ]] || return 0
    pgrep -qx "$app" || return 0
    _svc_stop "$app" || { REASON="$app will not exit"; return 1 }
    needs_restart "$app"
    return 0
}

_svc_start() {
    local app=$1 target=$2 attempt i
    local -a openarg
    if [[ "$target" == /* ]]; then
        [[ -e "$target" ]] || { REASON="not installed: $target"; return 1 }
        openarg=("$target")
    else
        open -Ra "$target" 2>/dev/null || { REASON="not installed: $target"; return 1 }
        openarg=(-a "$target")
    fi
    for attempt in 1 2 3; do
        open -g "${openarg[@]}" 2>/dev/null
        for i in {1..15}; do
            _svc_running "$app" && return 0
            cancelled && { REASON="cancelled"; return 1 }
            sleep 0.2
        done
    done
    REASON="did not come up after 3 attempts"
    return 1
}

service_check() {
    local app=${POS[1]}
    if restart_pending "$app"; then REASON="restart pending"; return 1; fi
    _svc_running "$app" && return 0
    REASON="not running"
    return 1
}

service_undo() {
    local id=$1 app=${POS[1]} target="${P[path]:-${POS[1]}}"
    if _svc_running "$app"; then
        if [[ "$target" == /* ]]; then
            undo_push "put $app back up" "open -g ${(q)target} 2>/dev/null; true"
        else
            undo_push "put $app back up" "open -g -a ${(q)target} 2>/dev/null; true"
        fi
    else
        undo_push "stop $app again" "pkill -x ${(q)app} 2>/dev/null; true"
    fi
    return 0
}

# The pending-restart flag is cleared only after the app is verified back up,
# so a failed relaunch retries on the next sync instead of being forgotten.
service_apply() {
    local app=${POS[1]} target="${P[path]:-${POS[1]}}"
    if [[ "${P[kind]:-}" == killall ]]; then
        killall "$app" 2>/dev/null
        local i
        for i in {1..25}; do
            _svc_running "$app" && { restart_done "$app"; return 0 }
            cancelled && { REASON="cancelled"; return 1 }
            sleep 0.2
        done
        REASON="$app did not respawn"
        return 1
    fi
    if restart_pending "$app" || _svc_running "$app"; then
        _svc_stop "$app" || { REASON="$app will not exit"; return 1 }
    fi
    _svc_start "$app" "$target" || return 1
    restart_done "$app"
    return 0
}

service_revert() {
    local app=${1#service:}
    # kind=killall means the OS owns the process and respawns it — the Dock. There
    # is no "stopped" state to revert to, and waiting for one would stall ten
    # seconds and then report a failure. Its restart is handled after the defaults
    # it reads have been rewritten, not here.
    [[ "${P[kind]:-}" == killall ]] && return 0
    _svc_stop "$app"
    return 0
}

service_describe() { print -r -- "${POS[1]}" }
