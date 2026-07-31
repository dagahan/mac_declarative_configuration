#!/usr/bin/env zsh
# Who is blocking every keyboard shortcut on this machine.
#
# macOS Secure Input (EnableSecureEventInput) stops ALL applications from reading
# key events. AeroSpace, Karabiner, AltTab and Ainto hotkeys go dead system-wide
# while the modifier still types its character — option+2 comes out as "™" and
# cmd+w stops being remapped. Nothing logs an error and every layer reports
# itself healthy, because every layer *is* healthy.
#
# Two different questions, and confusing them wasted hours here:
#   IsSecureEventInputEnabled()  — is it on right now? Authoritative.
#   kCGSSessionSecureInputPID    — which process turned it on last. Goes stale
#                                  when that process dies, and then names a pid
#                                  that no longer exists while the block is real.
set -uo pipefail

HERE="${0:A:h}"
BIN="${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup/cache/secure-input-state"
mkdir -p "${BIN:h}"
if [[ ! -x "$BIN" || "$HERE/secure-input-state.swift" -nt "$BIN" ]]; then
    swiftc -O -o "$BIN" "$HERE/secure-input-state.swift" 2>/dev/null
fi

state=$([[ -x "$BIN" ]] && "$BIN" 2>/dev/null || print -n "UNKNOWN")
pid=$(ioreg -l -w 0 2>/dev/null | LC_ALL=C sed -n 's/.*"kCGSSessionSecureInputPID"=\([0-9]*\).*/\1/p' | head -1)

if [[ "$state" == "OFF" ]]; then
    print -r -- "  Secure Input is OFF — it is not what is blocking your hotkeys"
    exit 0
fi

print -r -- ""
print -r -- "  Secure Input is ${state} — every keyboard shortcut on the machine is blocked."
print -r -- ""

if [[ -n "$pid" && "$pid" != "0" ]] && ps -p "$pid" >/dev/null 2>&1; then
    print -r -- "  Last enabled by, and still running:"
    ps -p "$pid" -o pid=,lstart=,command= 2>/dev/null | cut -c1-110 | sed 's/^/    /'
    print -r -- ""
    print -r -- "  Unfocus its password field, or quit that app, and shortcuts come back."
else
    print -r -- "  Last enabled by pid ${pid:-unknown}, which has exited — but the block is"
    print -r -- "  still live, so something else holds it too, or the count leaked."
    print -r -- ""
    print -r -- "  Quitting apps will not clear a leaked count. Log out and back in;"
    print -r -- "  a full reboot is not needed."
fi

print -r -- ""
print -r -- "  Running now, and known to take Secure Input:"
local a p found=0
for a in ChatGPT Bitwarden AyuGram Safari "Google Chrome" Yandex 1Password Terminal iTerm2; do
    p=$(pgrep -x "$a" 2>/dev/null | head -1)
    [[ -n "$p" ]] && { printf '    %-16s pid %s\n' "$a" "$p"; found=1 }
done
(( found )) || print -r -- "    (none)"
print -r -- ""
print -r -- "  Terminals are a common cause: Terminal.app and iTerm2 both have a"
print -r -- "  \"Secure Keyboard Entry\" menu item that pins this on for as long as they run."
print -r -- ""
exit 1
