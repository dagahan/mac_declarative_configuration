# The ledger answers one question: "is this mine to touch, and what was here
# before I arrived?" It is never asked what the machine currently looks like —
# that always comes from a live probe.
typeset -g STATE="${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup"
typeset -g LEDGER="$STATE/ledger.tsv"
typeset -gi SCHEMA=1
typeset -gA L_OWNED

state_init() { mkdir -p "$STATE"/{before,journal,cache,artifacts} }

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

_before_file() {
    local key="${1//[^a-zA-Z0-9._-]/_}"
    print -r -- "$STATE/before/$key"
}
before_save() {
    local f; f=$(_before_file "$1")
    [[ -e "$f" ]] || print -r -- "$2" > "$f"
}
before_get()    { local f; f=$(_before_file "$1"); [[ -e "$f" ]] && cat "$f" }
before_exists() { local f; f=$(_before_file "$1"); [[ -e "$f" ]] }
before_drop()   { local f; f=$(_before_file "$1"); rm -f "$f" }

lock_acquire() {
    local d="$STATE/lock" pid
    if mkdir "$d" 2>/dev/null; then print -r -- $$ > "$d/pid"; return 0; fi
    pid=$(cat "$d/pid" 2>/dev/null)
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

journal_open() {
    typeset -g JOURNAL="$STATE/journal/$(date '+%Y%m%d-%H%M%S').log"
    print -r -- "# mac $* @ $(date) $(os_name) $(os_build_now)" > "$JOURNAL"
}
journal() { [[ -n "${JOURNAL:-}" ]] && print -r -- "$@" >> "$JOURNAL" }
