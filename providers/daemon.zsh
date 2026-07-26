# A launchd job's *activation*, not its definition — the plist itself is an
# ordinary `file` resource. Same split the engine already makes between
# `default` (writes the preference) and `service` (restarts the app).
#
# The hash of the plist as it was at bootstrap is recorded, so editing the
# file shows up here as drift and the job gets re-loaded rather than silently
# running yesterday's definition.

_daemon_root()   { [[ -n "${P[root]:-}" ]] }
_daemon_domain() { _daemon_root && print -r -- "system" || print -r -- "gui/$UID" }
_daemon_plist()  {
    _daemon_root && print -r -- "/Library/LaunchDaemons/${P[label]}.plist" \
                 || print -r -- "$HOME/Library/LaunchAgents/${P[label]}.plist"
}
_daemon_stamp() { print -r -- "$STATE/daemons/${1//[^a-zA-Z0-9._-]/_}" }

_daemon_ctl() {
    if _daemon_root; then sudo -n launchctl "$@"; else launchctl "$@"; fi
}

_daemon_running() {
    local out
    out=$(_daemon_ctl print "$(_daemon_domain)/${P[label]}" 2>/dev/null) || return 2
    [[ "$out" == *"state = running"* ]] && return 0
    return 1
}

daemon_check() {
    local id=$1 plist; plist=$(_daemon_plist)
    [[ -f "$plist" ]] || { REASON="no plist at $plist"; return 1 }

    if _daemon_root && ! sudo -n true 2>/dev/null; then
        REASON="needs root to inspect — run 'sudo -v' then retry"
        return $TIMED_OUT
    fi

    local rc; _daemon_running; rc=$?
    (( rc == 2 )) && { REASON="not loaded"; return 1 }
    (( rc == 1 )) && { REASON="loaded but not running"; return 1 }

    local want have
    want=$(shasum -a 256 "$plist" | cut -d' ' -f1)
    have=$(cat "$(_daemon_stamp "$id")" 2>/dev/null)
    [[ "$want" == "$have" ]] && return 0
    REASON="definition changed since it was loaded"
    return 1
}

daemon_apply() {
    local id=$1 label="${P[label]}" dom plist i
    dom=$(_daemon_domain); plist=$(_daemon_plist)
    [[ -f "$plist" ]] || { REASON="no plist at $plist"; return 1 }

    if _daemon_root && ! sudo -n true 2>/dev/null; then
        REASON="needs root — run 'sudo -v' then retry"
        return 1
    fi

    before_exists "$id" || before_save "$id" "$dom/$label"

    _daemon_ctl bootout "$dom/$label" 2>/dev/null
    _daemon_ctl bootstrap "$dom" "$plist" 2>/dev/null \
        || { REASON="launchctl bootstrap refused $plist"; return 1 }
    _daemon_ctl kickstart -k "$dom/$label" 2>/dev/null

    for i in {1..25}; do
        _daemon_running && break
        sleep 0.2
    done
    if ! _daemon_running; then
        REASON="loaded but never reached running — see the job's stderr path"
        return 1
    fi

    mkdir -p "$STATE/daemons"
    shasum -a 256 "$plist" | cut -d' ' -f1 > "$(_daemon_stamp "$id")"
    return 0
}

daemon_revert() {
    local id=$1 rec
    rec=$(before_get "$id")
    [[ -n "$rec" ]] || { REASON="no record of this job"; return 1 }
    if [[ "$rec" == system/* ]]; then
        sudo -n launchctl bootout "$rec" 2>/dev/null
    else
        launchctl bootout "$rec" 2>/dev/null
    fi
    rm -f "$(_daemon_stamp "$id")"
    return 0
}

daemon_describe() { print -r -- "${P[label]}" }
