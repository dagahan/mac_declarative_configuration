# A step that takes time has to say so, and it may never be the thing that
# corrupts the terminal. Both rules live here: the spinner draws only when
# stdout is a live tty and the run is not verbose, and it is the only writer
# on its line — the engine prints nothing between spin_start and spin_stop.
typeset -g SPIN_PID='' SPIN_LABEL=''
typeset -gi SPIN_ON=0 SPIN_T0=0

zmodload -F zsh/stat b:zstat

_spin_drawable() { [[ -t 1 && -z "${NO_COLOR:-}" ]] && (( ! VERBOSE )) }

# The terminal a run was handed back in has to be the one it borrowed. A child
# that reads the tty — a sudo password prompt, an installer, anything killed
# while it had echo turned off — leaves the line discipline changed, and the
# symptom lands on the next prompt rather than in this run's output: keys stop
# echoing, or arrive as escape sequences the shell prints instead of obeying.
# Nothing in the engine can predict which child does it, so the state is simply
# recorded up front and put back on the way out.
typeset -g TTY_STATE=''

# The redirection itself is what fails when there is no controlling terminal —
# a cron run, a pipe — and zsh reports that before stty ever runs, so the whole
# thing is wrapped rather than just the command.
tty_save() {
    [[ -t 0 || -t 1 ]] || return 0
    TTY_STATE=$( { stty -g < /dev/tty } 2>/dev/null ) || TTY_STATE=''
    return 0
}

tty_restore() {
    [[ -n "$TTY_STATE" ]] || return 0
    { stty "$TTY_STATE" < /dev/tty } 2>/dev/null
    return 0
}

# Starting a spinner always stops the one before it. There is exactly one line
# being animated at a time, and exactly one pid to kill — a nested spin_start
# used to overwrite that pid and leave the outer spinner running forever, which
# survived the run that started it and scribbled over the prompt.
spin_start() {
    spin_stop
    SPIN_LABEL="$1"
    SPIN_T0=$EPOCHSECONDS
    if ! _spin_drawable; then
        print -r -- "  ${C_DIM}…${C_RESET} $SPIN_LABEL"
        return 0
    fi
    typeset -g SPIN_PARENT=$$
    printf '\033[?25l'
    (
        trap 'printf "\033\033[0m\r\033[2K\033[?25h"; exit 0' TERM INT
        local -a f
        f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        local -i i=1 el
        while :; do
            # Never outlive whatever started it. A spinner is decoration; if the
            # run it belongs to is gone, so is any reason to keep drawing.
            kill -0 "$SPIN_PARENT" 2>/dev/null || { printf '\r\033[2K\033[?25h'; exit 0 }
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
    if [[ -n "$SPIN_PID" ]]; then
        # TERM, not KILL. A -9 lands wherever the renderer happens to be, and
        # when that is halfway through an escape sequence the terminal is left
        # parsing a sequence that never ends — every key pressed afterwards gets
        # swallowed into it or echoed back as garbage. The handler finishes its
        # write and clears the line, so the tty is handed back whole.
        kill -TERM "$SPIN_PID" 2>/dev/null
        local -i i
        for i in {1..40}; do
            kill -0 "$SPIN_PID" 2>/dev/null || break
            sleep 0.005
        done
        kill -9 "$SPIN_PID" 2>/dev/null
        SPIN_PID=''
    fi
    (( SPIN_ON )) || return 0
    SPIN_ON=0
    # Belt and braces for the -9 above: a lone ESC aborts whatever sequence the
    # terminal may still be waiting to finish, so the reset that follows is read
    # as a reset rather than as arguments to a half-written command.
    printf '\033\033[0m\r\033[2K\033[?25h'
    return 0
}

spin_elapsed() { print -r -- $(( EPOCHSECONDS - SPIN_T0 )) }

# ── progress ──────────────────────────────────────────────────────────────
#
# A spinner is an honest answer to "is this still alive" and a useless one to
# "how much longer". A multi-gigabyte download needs the second question
# answered, so this draws the same single animated line with the numbers that
# only a transfer has: how much of how much, how fast, and how long is left.
#
# It watches a file grow rather than parsing the downloader's own output. Curl's
# progress meter cannot be let near the terminal — raw carriage returns from a
# child are exactly what leaves a tty in a state where ^C stops working — and
# the size of the part file on disk is the same truth without the hazard.

fmt_bytes() {
    local -F b=$1
    if   (( b >= 1073741824 )); then printf '%.1f GiB' $(( b / 1073741824. ))
    elif (( b >= 1048576 ));    then printf '%.1f MiB' $(( b / 1048576. ))
    elif (( b >= 1024 ));       then printf '%.0f KiB' $(( b / 1024. ))
    else                             printf '%d B' $(( b ))
    fi
}

fmt_dur() {
    local -i s=$1
    (( s < 0 )) && s=0
    if   (( s >= 3600 )); then printf '%dh%02dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
    elif (( s >= 60 ));   then printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
    else                       printf '%ds' $s
    fi
}

_prog_size() {
    local -a s
    zstat -A s +size "$1" 2>/dev/null || { print -r -- 0; return }
    print -r -- "${s[1]:-0}"
}

# Newest match, or empty. Ordered by mtime so the one still being written wins
# over any part file an earlier run abandoned.
_prog_newest() {
    local -a m
    m=(${~1}(N.om))
    print -r -- "${m[1]:-}"
}

# <sha>--android-studio-quail3-mac_arm.dmg.incomplete → android-studio-quail3-mac_arm.
# Only the extension is cut, never everything after the first dot: versions have
# dots in them, and "my-cask-1" is a worse answer than a slightly long one.
_prog_name() {
    local n=${1:t}
    n=${n#*--}
    n=${n%.incomplete}
    print -r -- "${n%.*}"
}

# prog_start <label> <file> <total-bytes|0>
#
# Deliberately reuses SPIN_PID and SPIN_ON. Every path that already ends a
# spinner — spin_stop, TRAPINT, TRAPTERM, TRAPEXIT — then ends a progress line
# too, so ^C during a download cannot leave a renderer drawing over the prompt.
prog_start() {
    spin_stop
    local label=$1 file=$2
    local -i total=$3
    SPIN_LABEL="$label"
    SPIN_T0=$EPOCHSECONDS
    if ! _spin_drawable; then
        if (( total > 0 )); then
            print -r -- "  ${C_DIM}…${C_RESET} $label ${C_DIM}($(fmt_bytes $total))${C_RESET}"
        else
            print -r -- "  ${C_DIM}…${C_RESET} $label"
        fi
        return 0
    fi
    typeset -g SPIN_PARENT=$$
    printf '\033[?25l'
    (
        trap 'printf "\033\033[0m\r\033[2K\033[?25h"; exit 0' TERM INT
        local -a f
        f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        local -i i=1 cur=0 done_w=0 bar_w=22 pct=0 eta=0 cols=0
        local -F now=0 mark=$EPOCHREALTIME rate=0 inst=0
        local -i marked=$(_prog_size "$file")
        local body bar
        while :; do
            kill -0 "$SPIN_PARENT" 2>/dev/null || { printf '\r\033[2K\033[?25h'; exit 0 }
            cur=$(_prog_size "$file")
            now=$EPOCHREALTIME
            # Sampled on a floor of half a second: over a shorter window the
            # figure is mostly jitter, and a number that flickers reads as
            # noise rather than as speed.
            if (( now - mark >= 0.5 )); then
                inst=$(( (cur - marked) / (now - mark) ))
                (( inst < 0 )) && inst=0
                (( rate = rate > 0 ? rate * 0.7 + inst * 0.3 : inst ))
                marked=$cur; mark=$now
            fi
            body="$SPIN_LABEL"
            if (( total > 0 )); then
                pct=$(( cur * 100 / total ))
                (( pct > 100 )) && pct=100
                done_w=$(( bar_w * pct / 100 ))
                bar="${(l:done_w::█:)}${(l:$(( bar_w - done_w ))::░:)}"
                body+="  ▕${bar}▏ ${(l:3:)pct}%  $(fmt_bytes $cur)/$(fmt_bytes $total)"
            else
                body+="  $(fmt_bytes $cur)"
            fi
            if (( rate > 0 )); then
                body+="  $(fmt_bytes $rate)/s"
                if (( total > 0 && cur < total )); then
                    eta=$(( (total - cur) / rate ))
                    body+="  ${C_DIM}eta $(fmt_dur $eta)${C_RESET}"
                fi
            fi
            # Truncated rather than wrapped: a line that wraps is a line the
            # next redraw cannot erase, and the terminal fills with bars.
            cols=${COLUMNS:-80}
            (( ${#body} > cols - 6 )) && body="${body[1,cols-6]}"
            printf '\r\033[2K  %s%s%s %s' "$C_BLU" "${f[i]}" "$C_RESET" "$body"
            (( i = i % ${#f} + 1 ))
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
    SPIN_ON=1
}

# prog_start_glob <label> <glob>
#
# prog_start for a transfer whose file is not known when the step begins.
# Homebrew fetches one package after another inside a single `brew bundle`, each
# to its own part file, so the glob is re-resolved every tick and the line
# follows whatever is being pulled now — and shows the label alone in between,
# while a dmg is mounted and copied.
#
# No bar and no eta: brew does not say how big the download is before it starts,
# and a bar drawn against a guessed total is a worse answer than a byte count
# that is simply true.
prog_start_glob() {
    spin_stop
    local label=$1 pattern=$2
    SPIN_LABEL="$label"
    SPIN_T0=$EPOCHSECONDS
    if ! _spin_drawable; then
        print -r -- "  ${C_DIM}…${C_RESET} $label"
        return 0
    fi
    typeset -g SPIN_PARENT=$$
    printf '\033[?25l'
    (
        trap 'printf "\033\033[0m\r\033[2K\033[?25h"; exit 0' TERM INT
        local -a f
        f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        local -i i=1 cur=0 cols=0 el=0
        local -F now=0 mark=$EPOCHREALTIME rate=0 inst=0
        local -i marked=0
        local body file last=''
        while :; do
            kill -0 "$SPIN_PARENT" 2>/dev/null || { printf '\r\033[2K\033[?25h'; exit 0 }
            file=$(_prog_newest "$pattern")
            # A different part file is a different transfer. Carrying the rate
            # across would measure the new file's bytes against the old one's
            # clock and print a number that was never true of either.
            if [[ "$file" != "$last" ]]; then
                last="$file"; rate=0
                marked=$(_prog_size "$file"); mark=$EPOCHREALTIME
            fi
            body="$SPIN_LABEL"
            if [[ -n "$file" ]]; then
                cur=$(_prog_size "$file")
                now=$EPOCHREALTIME
                if (( now - mark >= 0.5 )); then
                    inst=$(( (cur - marked) / (now - mark) ))
                    (( inst < 0 )) && inst=0
                    (( rate = rate > 0 ? rate * 0.7 + inst * 0.3 : inst ))
                    marked=$cur; mark=$now
                fi
                body+="  ${C_DIM}$(_prog_name "$file")${C_RESET}  $(fmt_bytes $cur)"
                (( rate > 0 )) && body+="  $(fmt_bytes $rate)/s"
            else
                el=$(( EPOCHSECONDS - SPIN_T0 ))
                (( el >= 2 )) && body+="  ${C_DIM}${el}s${C_RESET}"
            fi
            cols=${COLUMNS:-80}
            (( ${#body} > cols - 6 )) && body="${body[1,cols-6]}"
            printf '\r\033[2K  %s%s%s %s' "$C_BLU" "${f[i]}" "$C_RESET" "$body"
            (( i = i % ${#f} + 1 ))
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
    SPIN_ON=1
}

prog_stop() { spin_stop }
