#!/usr/bin/env zsh
# Catches the app that turns Secure Input on.
#
# The block is system-wide and silent, and by the time hotkeys are noticed dead
# the culprit may have exited — leaving `kCGSSessionSecureInputPID` pointing at a
# pid that no longer exists. Polling for the edge records who did it *at the
# moment it happened*, plus what was frontmost, which is the part that identifies
# the password field responsible.
set -uo pipefail

HERE="${0:A:h}"
LOG="${MAC_SECURE_INPUT_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup/secure-input.log}"
BIN="${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup/cache/secure-input-state"
INTERVAL="${MAC_SECURE_INPUT_INTERVAL:-2}"

mkdir -p "${LOG:h}" "${BIN:h}"
[[ -x "$BIN" ]] || swiftc -O -o "$BIN" "$HERE/secure-input-state.swift" 2>/dev/null
[[ -x "$BIN" ]] || { print -ru2 -- "cannot build the state probe"; exit 1 }

note() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" }

holder_pid() {
    ioreg -l -w 0 2>/dev/null | LC_ALL=C sed -n 's/.*"kCGSSessionSecureInputPID"=\([0-9]*\).*/\1/p' | head -1
}
frontmost() {
    lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | cut -d'"' -f4
}

notify() {
    osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1
}

prev=$("$BIN")
note "watch started — Secure Input is $prev"
on_since=0

while :; do
    sleep "$INTERVAL"
    now=$("$BIN")
    if [[ "$now" != "$prev" ]]; then
        if [[ "$now" == "ON" ]]; then
            pid=$(holder_pid)
            who=$(ps -p "$pid" -o comm= 2>/dev/null)
            front=$(frontmost)
            note "TURNED ON  enabler=pid ${pid:-?} ${who:-<already gone>}  frontmost=$front"
            ps -p "$pid" -o pid=,lstart=,command= 2>/dev/null | cut -c1-140 | sed 's/^/    /' >> "$LOG"
            on_since=$SECONDS
            if [[ -n "$who" ]]; then
                notify "Secure Input: ${who:t}" "Frontmost app: $front. Hotkeys keep working through Karabiner."
            else
                notify "Secure Input is stuck" "The app that took it has quit. Lock and unlock the screen (ctrl+cmd+Q) to release it."
            fi
        else
            note "turned off — released after $(( SECONDS - on_since ))s"
        fi
        prev="$now"
    fi
done
