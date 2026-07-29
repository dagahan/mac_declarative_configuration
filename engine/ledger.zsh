# The ledger answers one question: "is this mine to touch?" It is never asked what
# the machine currently looks like — that always comes from a live probe — and it
# no longer claims to know what the machine looked like before mac_setup arrived.
# That claim was a fiction: whichever sync ran first decided what "before" meant,
# and for most keys nothing was ever recorded, so reverting quietly became
# deleting. Units declare their own off state with on_workspace_down= instead.
zmodload zsh/datetime
typeset -g STATE="${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup"
typeset -g LEDGER="$STATE/ledger.tsv"
typeset -gi SCHEMA=1
typeset -gA L_OWNED

state_init() {
    mkdir -p "$STATE"/{placed,journal,cache,artifacts,pending-restart,files,daemons}
    _placement_migrate
}

# $STATE/before held two unrelated things under one name: guesses at prior state,
# and the only record of *where* a resource put something. The first is gone; the
# second has to survive, or prune can no longer find what it needs to remove.
_placement_migrate() {
    [[ -d "$STATE/before" ]] || return 0
    local f
    for f in "$STATE"/before/*(N); do
        [[ "${f:t}" == default_* ]] && continue
        [[ -e "$STATE/placed/${f:t}" ]] || mv "$f" "$STATE/placed/${f:t}"
    done
    rm -rf "$STATE/before"
}

needs_restart()    { mkdir -p "$STATE/pending-restart"; touch "$STATE/pending-restart/$1" }
restart_pending()  { [[ -f "$STATE/pending-restart/$1" ]] }
restart_done()     { rm -f "$STATE/pending-restart/$1" }

ledger_load() {
    L_OWNED=()
    [[ -f "$LEDGER" ]] || return 0
    local id rest ver
    ver=$(head -1 "$LEDGER" | cut -f2)
    [[ "$ver" == <-> ]] || die "unreadable ledger header: $LEDGER"
    (( ver <= SCHEMA )) || die "ledger schema v$ver is newer than this engine (v$SCHEMA) — update mac_setup"
    while IFS=$'\t' read -r id rest; do
        [[ "$id" == "schema" || -z "$id" ]] && continue
        L_OWNED[$id]="$rest"
    done < "$LEDGER"
}

ledger_save() {
    local tmp="$LEDGER.tmp.$$" id
    {
        print -r -- "schema$(printf '\t')$SCHEMA"
        for id in "${(@k)L_OWNED}"; do print -r -- "$id$(printf '\t')${L_OWNED[$id]}"; done
    } > "$tmp" || die "cannot write ledger"
    [[ -f "$LEDGER" ]] && cp -f "$LEDGER" "$LEDGER.bak"
    mv -f "$tmp" "$LEDGER"
}

ledger_owned()  { [[ -n "${L_OWNED[$1]:-}" ]] }
ledger_claim()  {
    local id=$1 now
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local first="${${(s:	:)L_OWNED[$id]}[3]:-$now}"
    L_OWNED[$id]="${R_PROVIDER[$id]}$(printf '\t')${R_UNIT[$id]}$(printf '\t')$first$(printf '\t')$now"
}
ledger_release() { unset "L_OWNED[$1]" }

# Where a resource put something — a daemon's launchd domain, an app's install
# path, a file's destination. Not a snapshot of prior state: by the time we revert,
# the declaration has been deleted from the repo and the id is all we have left.
_placement_file() {
    local key="${1//[^a-zA-Z0-9._-]/_}"
    print -r -- "$STATE/placed/$key"
}
placement_save() {
    local f; f=$(_placement_file "$1")
    [[ -e "$f" ]] || print -r -- "$2" > "$f"
}
placement_get()    { local f; f=$(_placement_file "$1"); [[ -e "$f" ]] && cat "$f" }
placement_exists() { local f; f=$(_placement_file "$1"); [[ -e "$f" ]] }
placement_drop()   { local f; f=$(_placement_file "$1"); rm -f "$f" }

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
