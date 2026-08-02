# A launchd job's *activation*, not its definition — the plist itself is an
# ordinary `file` resource. Same split the engine already makes between
# `default` (writes the preference) and `service` (restarts the app).
#
# The hash of the plist as it was at bootstrap is recorded, so editing the
# file shows up here as drift and the job gets re-loaded rather than silently
# running yesterday's definition.

_daemon_root()   { [[ -n "${P[root]:-}" ]] }
_daemon_domain() { _daemon_root && print -r -- "system" || print -r -- "gui/$UID" }

# plist= keeps a job out of /Library/LaunchDaemons and ~/Library/LaunchAgents,
# the two directories launchd scans on its own at boot and at login. A job
# declared with an explicit path is loaded only when something bootstraps it,
# so a reboot can never bring it back by itself.
_daemon_plist()  {
    if [[ -n "${P[plist]:-}" ]]; then print -r -- "${${P[plist]}/#\~/$HOME}"; return; fi
    _daemon_root && print -r -- "/Library/LaunchDaemons/${P[label]}.plist" \
                 || print -r -- "$HOME/Library/LaunchAgents/${P[label]}.plist"
}
_daemon_stamp() { print -r -- "$STATE/daemons/${1//[^a-zA-Z0-9._-]/_}" }

# The plist plus every config the job actually reads. Without watch=, editing
# a program's config would leave it running yesterday's settings, because the
# plist never changed and nothing else here would notice.
_daemon_fp() {
    local f
    {
        shasum -a 256 "$(_daemon_plist)"
        for f in ${=P[watch]:-}; do shasum -a 256 "${f/#\~/$HOME}" 2>/dev/null; done
    } | shasum -a 256 | cut -d' ' -f1
}

_daemon_ctl() {
    if _daemon_root; then sudo -n launchctl "$@"; else launchctl "$@"; fi
}

_daemon_running() {
    local out
    out=$(_daemon_ctl print "$(_daemon_domain)/${P[label]}" 2>/dev/null) || return 2
    # An interval job spends almost all its life not running; for those, being
    # loaded is the whole of what we can assert.
    [[ -n "${P[periodic]:-}" ]] && return 0
    [[ "$out" == *"state = running"* ]] && return 0
    return 1
}

daemon_check() {
    local id=$1 plist; plist=$(_daemon_plist)
    [[ -f "$plist" ]] || { REASON="no plist at $plist"; return 1 }

    # Without a cached sudo we cannot ask launchd about a system job. For a
    # long-running one the process itself is decent evidence; for an interval
    # job there is no process to find between runs, so guessing "not running"
    # would invent drift and re-apply something already loaded. Say unknown.
    if _daemon_root && ! sudo -n true 2>/dev/null; then
        [[ -n "${P[periodic]:-}" ]] && { REASON="needs your password to tell"; return 2 }
        pgrep -qx "${P[label]##*.}" && return 0
        REASON="not running"
        return 1
    fi

    local rc; _daemon_running; rc=$?
    (( rc == 2 )) && { REASON="not loaded"; return 1 }
    (( rc == 1 )) && { REASON="loaded but not running"; return 1 }

    local want have
    want=$(_daemon_fp)
    have=$(cat "$(_daemon_stamp "$id")" 2>/dev/null)
    [[ "$want" == "$have" ]] && return 0
    REASON="definition or config changed since it was loaded"
    return 1
}

# Whether the job was loaded, and under which definition. The plist file itself
# is an ordinary `file` resource with an undo of its own, so all that has to be
# recorded here is the load state it was found in.
daemon_undo() {
    local id=$1 label="${P[label]}" dom plist stamp ctl blob
    dom=$(_daemon_domain); plist=$(_daemon_plist); stamp=$(_daemon_stamp "$id")
    ctl="launchctl"; _daemon_root && ctl="sudo -n launchctl"
    if _daemon_ctl print "$dom/$label" >/dev/null 2>&1; then
        undo_push "reload $label" \
            "$ctl bootout ${(q)dom}/${(q)label} 2>/dev/null; $ctl bootstrap ${(q)dom} ${(q)plist} 2>/dev/null; true"
    else
        undo_push "unload $label" "$ctl bootout ${(q)dom}/${(q)label} 2>/dev/null; true"
    fi
    if [[ -e "$stamp" ]] && blob=$(undo_backup "$stamp"); then
        undo_push "restore stamp for $label" "cp -p ${(q)blob} ${(q)stamp}"
    else
        undo_push "clear stamp for $label" "rm -f ${(q)stamp}"
    fi
    return 0
}

daemon_apply() {
    local id=$1 label="${P[label]}" dom plist i
    dom=$(_daemon_domain); plist=$(_daemon_plist)
    [[ -f "$plist" ]] || { REASON="no plist at $plist"; return 1 }

    if _daemon_root && ! sudo -n true 2>/dev/null; then
        REASON="root access expired mid-run"
        return 1
    fi

    # A guard is the difference between "start the job" and "start the job only
    # if the thing it depends on is genuinely working". sing-box captures all
    # routing the instant it loads; if its upstream proxy is dead, that is a
    # total network outage rather than a failed unit.
    # From $ROOT, like the run provider: a guard written against repo-relative
    # paths would otherwise fail purely because of where you happened to be
    # standing when you typed the command.
    if [[ -n "${P[guard]:-}" ]]; then
        if ! ( cd "$ROOT" && eval "${P[guard]}" ) >/dev/null 2>&1; then
            REASON="guard failed: ${P[guard]}"
            return 1
        fi
    fi

    # bootout returns before the job is actually gone; bootstrapping into a
    # domain that still holds the old label is refused outright.
    _daemon_ctl bootout "$dom/$label" 2>/dev/null
    for i in {1..40}; do
        _daemon_ctl print "$dom/$label" >/dev/null 2>&1 || break
        cancelled && { REASON="cancelled"; return 1 }
        sleep 0.25
    done
    _daemon_ctl bootstrap "$dom" "$plist" 2>/dev/null \
        || { REASON="launchctl bootstrap refused $plist"; return 1 }
    _daemon_ctl kickstart -k "$dom/$label" 2>/dev/null

    for i in {1..25}; do
        _daemon_running && break
        cancelled && { REASON="cancelled"; return 1 }
        sleep 0.2
    done
    if ! _daemon_running; then
        REASON="loaded but never reached running — see the job's stderr path"
        return 1
    fi

    mkdir -p "$STATE/daemons"
    _daemon_fp > "$(_daemon_stamp "$id")"
    return 0
}

daemon_revert() {
    local id=$1 label="${P[label]}" dom
    dom=$(_daemon_domain)
    [[ -n "$label" ]] || { REASON="no label to unload"; return 1 }
    _daemon_ctl bootout "$dom/$label" 2>/dev/null
    rm -f "$(_daemon_stamp "$id")"
    return 0
}

daemon_describe() { print -r -- "${P[label]}" }
