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
    osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null
}

notify() {
    osascript -e "display notification \"$1\" with title \"Hotkeys blocked\" sound name \"Basso\"" >/dev/null 2>&1
}

# A password field holds Secure Input for seconds. Anything still holding it after
# this long has leaked it, and every shortcut on the machine stays dead until that
# app is quit — worth interrupting for, because nothing else tells you.
STUCK_AFTER="${MAC_SECURE_INPUT_STUCK_AFTER:-30}"

prev=$("$BIN")
note "watch started — Secure Input is $prev"
on_since=0
warned=0

while :; do
    sleep "$INTERVAL"
    now=$("$BIN")
    if [[ "$now" != "$prev" ]]; then
        if [[ "$now" == "ON" ]]; then
            pid=$(holder_pid)
            who=$(ps -p "$pid" -o comm= 2>/dev/null)
            note "TURNED ON  enabler=pid ${pid:-?} ${who:-<already gone>}  frontmost=$(frontmost)"
            ps -p "$pid" -o pid=,lstart=,command= 2>/dev/null | cut -c1-140 | sed 's/^/    /' >> "$LOG"
            on_since=$SECONDS
            warned=0
        else
            note "turned off — released after $(( SECONDS - on_since ))s"
            on_since=0
            warned=0
        fi
        prev="$now"
        continue
    fi
    # Unchanged: only interesting if it has been ON too long to be a real password field.
    if [[ "$now" == "ON" ]] && (( on_since > 0 && ! warned && SECONDS - on_since >= STUCK_AFTER )); then
        warned=1
        pid=$(holder_pid)
        who=$(ps -p "$pid" -o comm= 2>/dev/null | sed 's|.*/||')
        note "STUCK — ${who:-pid $pid} has held Secure Input for ${STUCK_AFTER}s; all hotkeys are blocked"
        notify "${who:-A process} is blocking every hotkey. Run: mac do hotkeys"
    fi
done
