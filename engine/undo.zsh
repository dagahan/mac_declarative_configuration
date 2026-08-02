# Applying one resource is an atom: it either lands whole or it leaves nothing
# behind. Before a provider touches anything it records how to put that thing
# back; the record is a file on disk, so a kill -9 does not lose it.
#
# The atom is one resource, not one run. Interrupting the twentieth step must
# not undo the nineteen that already succeeded — those are finished work, and
# unwinding them would turn a cancelled sync into a wrecked desktop.
typeset -g UNDO_DIR=''
typeset -gi UNDO_N=0 CANCELLED=0 ROLLING_BACK=0 CANCEL_HITS=0

undo_open() {
    UNDO_DIR="$STATE/undo/$$"
    rm -rf "$UNDO_DIR"
    mkdir -p "$UNDO_DIR/blobs"
    UNDO_N=0
    print -r -- "$1" > "$UNDO_DIR/what"
    print -r -- "$$"  > "$UNDO_DIR/pid"
}

# Inverses are shell, not data: restoring a launchd job, a defaults key and a
# directory tree have nothing in common except that each is one line to run.
# The counter is bumped in the current shell and only then formatted. Doing it
# inside the redirection — `> "$dir/$(printf %04d $(( ++UNDO_N )))"` — increments
# in the subshell the command substitution forks, so every push lands on the
# same filename and silently overwrites the one before it.
undo_push() {
    [[ -n "$UNDO_DIR" && -d "$UNDO_DIR" ]] || return 0
    local label=$1; shift
    local f
    (( ++UNDO_N ))
    f=$(printf '%s/%04d' "$UNDO_DIR" "$UNDO_N")
    { print -r -- "$label"; print -r -- "$*" } > "$f"
}

# Copies a path aside and prints where it went, so the caller can build an
# inverse that refers to it. Fails when there is nothing there — the caller
# then records "it did not exist" instead, which is a different inverse.
# Named after the path it copies, not from a counter: callers reach this through
# `blob=$(undo_backup ...)`, and a counter bumped inside that command
# substitution would be forgotten the moment the subshell exits — every copy
# would land on the same name and clobber the one before it. A path is unique
# and needs no shared state to stay that way.
undo_backup() {
    local src=$1 blob key
    [[ -n "$UNDO_DIR" && -d "$UNDO_DIR" ]] || return 1
    [[ -e "$src" || -L "$src" ]] || return 1
    key="${src//[^a-zA-Z0-9._-]/_}"
    blob="$UNDO_DIR/blobs/${key: -120}"
    rm -rf "$blob"
    cp -pR "$src" "$blob" 2>/dev/null || return 1
    print -r -- "$blob"
}

undo_commit() {
    [[ -n "$UNDO_DIR" ]] && rm -rf "$UNDO_DIR"
    UNDO_DIR=''
    return 0
}

undo_pending() {
    [[ -n "$UNDO_DIR" && -d "$UNDO_DIR" ]] || return 1
    local -a s; s=("$UNDO_DIR"/<->(N))
    (( ${#s} ))
}

undo_rollback() {
    undo_pending || { undo_commit; return 0 }
    local -a steps; steps=("$UNDO_DIR"/<->(Nn))
    local f label body i
    ROLLING_BACK=1
    print -r -- "  ${C_DIM}restoring ${#steps} change(s)${C_RESET}"
    for (( i = ${#steps}; i >= 1; i-- )); do
        f=${steps[i]}
        label=$(head -1 "$f")
        body=$(tail -n +2 "$f")
        if eval "$body" >/dev/null 2>&1; then
            print -r -- "    $S_OK ${C_DIM}$label${C_RESET}"
            journal "undo ok: $label"
        else
            print -r -- "    $S_BAD $label ${C_DIM}— could not undo${C_RESET}"
            journal "undo FAILED: $label"
        fi
        rm -f "$f"
    done
    ROLLING_BACK=0
    undo_commit
}

# A run killed outright leaves its record behind. The next run finishes the job
# rather than leaving a half-written file to be discovered later by whatever
# breaks because of it.
undo_recover() {
    local d pid
    for d in "$STATE"/undo/*(N/); do
        pid=$(cat "$d/pid" 2>/dev/null)
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && continue
        UNDO_DIR="$d"
        if undo_pending; then
            print -r -- ""
            print -r -- "  $S_WARN a previous run was killed while writing ${C_BOLD}$(cat "$d/what" 2>/dev/null)${C_RESET}"
            undo_rollback
            print -r -- ""
        else
            undo_commit
        fi
    done
    UNDO_DIR=''
}

cancelled() { (( CANCELLED )) }

# Returning 0 tells zsh the interrupt is handled and execution continues, so the
# apply loop gets to unwind deliberately instead of the shell dying mid-write.
# The child that was running has already taken the same SIGINT and exited.
TRAPINT() {
    if (( ROLLING_BACK )); then
        (( ++CANCEL_HITS ))
        if (( CANCEL_HITS >= 3 )); then
            spin_stop
            # The record is deliberately left on disk and only dropped from
            # memory, so the exit handler does not quietly finish the rollback
            # we just said we had abandoned — and the next run still can.
            UNDO_DIR=''
            tty_say ""
            tty_say "  ${C_RED}abandoned mid-restore — this machine is in a mixed state${C_RESET}"
            tty_say "  ${C_DIM}the next mac run will finish putting it back${C_RESET}"
            journal "ABORT during rollback"
            lock_release
            exit 130
        fi
        tty_say "  ${C_DIM}restoring — $(( 3 - CANCEL_HITS )) more ^C to abandon${C_RESET}"
        return 0
    fi
    CANCELLED=1
    spin_stop
    (( ${+functions[sh_kill_child]} )) && sh_kill_child
    tty_say "  ${C_YEL}cancelling${C_RESET}${C_DIM} — putting back what was mid-write${C_RESET}"
    return 0
}

TRAPTERM() {
    CANCELLED=1
    spin_stop
    (( ${+functions[sh_kill_child]} )) && sh_kill_child
    return 0
}
