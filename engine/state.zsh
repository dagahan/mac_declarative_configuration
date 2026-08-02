# Everything under $STATE is a cache, not a database. Fingerprints that say
# whether a file still matches what was written, build stamps, artifacts, the
# journal, and the undo record of whatever is being written right now. Delete
# the lot and nothing is lost but the time it takes to work it out again.
#
# There is deliberately no record of what the machine looked like before
# mac_setup arrived. That claim was a fiction — whichever sync ran first decided
# what "before" meant — and units declare their own off state with
# on_workspace_down= instead.
zmodload zsh/datetime
typeset -g STATE="${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup"

state_init() {
    mkdir -p "$STATE"/{journal,cache,artifacts,pending-restart,files,daemons,builds,undo,downloads}
    _state_retire
}

# One-time cleanup of directories earlier engines kept: the ledger and its
# before-images, the placement store that only prune ever read, and the ack
# markers that stood in for a manual step that could not check itself.
_state_retire() {
    local d
    for d in before placed ack; do
        [[ -d "$STATE/$d" ]] && rm -rf "$STATE/$d"
    done
    rm -f "$STATE/ledger.tsv" "$STATE/ledger.tsv.bak"
    return 0
}

needs_restart()    { mkdir -p "$STATE/pending-restart"; touch "$STATE/pending-restart/$1" }
restart_pending()  { [[ -f "$STATE/pending-restart/$1" ]] }
restart_done()     { rm -f "$STATE/pending-restart/$1" }

lock_acquire() {
    local d="$STATE/lock" pid
    if mkdir "$d" 2>/dev/null; then print -r -- $$ > "$d/pid"; return 0; fi
    pid=$(cat "$d/pid" 2>/dev/null)
    # Re-entrant for one process: `mac workspace reload` is a teardown followed by
    # a sync in the same shell, and the second would otherwise mistake the first
    # for a competing run and refuse to start.
    [[ "$pid" == $$ ]] && return 0
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        die "another mac run is in progress (pid $pid)"
    fi
    rm -rf "$d"
    mkdir "$d" 2>/dev/null || die "cannot acquire lock at $d"
    print -r -- $$ > "$d/pid"
}
lock_release() { rm -rf "$STATE/lock" }

os_build_now()    { sw_vers -buildVersion 2>/dev/null }
os_build_last()   { cat "$STATE/os_build" 2>/dev/null }
os_build_record() { os_build_now > "$STATE/os_build" }
os_name()         { print -r -- "macOS $(sw_vers -productVersion 2>/dev/null)" }

# Every command gets a journal, not just the ones that change things — when
# something goes wrong at 2am the question is always "what did I actually run",
# and a command that leaves no trace cannot answer it. Idempotent, because the
# entry point opens one and cmd_sync and friends still ask for their own.
journal_open() {
    [[ -n "${JOURNAL:-}" ]] && return 0
    mkdir -p "$STATE/journal"
    # $$ included: two commands started in the same second would otherwise share
    # a filename, and the second would truncate the first one's record.
    typeset -g JOURNAL="$STATE/journal/$(date '+%Y%m%d-%H%M%S')-$$-${1:-run}.log"
    typeset -gi JOURNAL_T0=$EPOCHSECONDS
    print -r -- "# mac $* @ $(date) $(os_name) $(os_build_now)" > "$JOURNAL"
    journal_prune
}

journal() { [[ -n "${JOURNAL:-}" ]] && print -r -- "$@" >> "$JOURNAL" }

journal_close() {
    [[ -n "${JOURNAL:-}" ]] || return 0
    print -r -- "# exit ${1:-0} after $(( EPOCHSECONDS - ${JOURNAL_T0:-EPOCHSECONDS} ))s" >> "$JOURNAL"
}

# Unbounded logs are their own failure mode.
journal_prune() {
    local -a old
    old=("$STATE"/journal/*.log(Nm+30))
    (( ${#old} )) && rm -f -- "${old[@]}"
    old=("$STATE"/journal/*.log(Nom[201,-1]))
    (( ${#old} )) && rm -f -- "${old[@]}"
    return 0
}
