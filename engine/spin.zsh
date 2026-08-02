# A step that takes time has to say so, and it may never be the thing that
# corrupts the terminal. Both rules live here: the spinner draws only when
# stdout is a live tty and the run is not verbose, and it is the only writer
# on its line — the engine prints nothing between spin_start and spin_stop.
typeset -g SPIN_PID='' SPIN_LABEL=''
typeset -gi SPIN_ON=0 SPIN_T0=0

_spin_drawable() { [[ -t 1 && -z "${NO_COLOR:-}" ]] && (( ! VERBOSE )) }

spin_start() {
    SPIN_LABEL="$1"
    SPIN_T0=$EPOCHSECONDS
    if ! _spin_drawable; then
        print -r -- "  ${C_DIM}…${C_RESET} $SPIN_LABEL"
        return 0
    fi
    printf '\033[?25l'
    (
        local -a f
        f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        local -i i=1 el
        while :; do
            el=$(( EPOCHSECONDS - SPIN_T0 ))
            # Elapsed only once a step is slow enough to make you wonder.
            if (( el >= 2 )); then
                printf '\r\033[2K  %s%s%s %s  %s%ds%s' \
                    "$C_BLU" "${f[i]}" "$C_RESET" "$SPIN_LABEL" "$C_DIM" "$el" "$C_RESET"
            else
                printf '\r\033[2K  %s%s%s %s' "$C_BLU" "${f[i]}" "$C_RESET" "$SPIN_LABEL"
            fi
            (( i = i % ${#f} + 1 ))
            sleep 0.08
        done
    ) &
    SPIN_PID=$!
    SPIN_ON=1
}

# Idempotent, and safe to call from a signal handler: every exit path runs it,
# and a cursor left hidden outlives the process that hid it.
#
# kill -9 and no wait. The spinner has nothing to flush, and waiting on it is
# what turned a cosmetic helper into a hang: a disowned job is not a child zsh
# will ever reap, so `wait` on it never returns.
spin_stop() {
    (( SPIN_ON )) || return 0
    SPIN_ON=0
    if [[ -n "$SPIN_PID" ]]; then
        kill -9 "$SPIN_PID" 2>/dev/null
        SPIN_PID=''
    fi
    printf '\r\033[2K\033[?25h'
    return 0
}

spin_elapsed() { print -r -- $(( EPOCHSECONDS - SPIN_T0 )) }
