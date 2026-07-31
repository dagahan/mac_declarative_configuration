#!/usr/bin/env zsh
# Why are my hotkeys dead? Run this first, always.
#
#   mac do hotkeys        diagnose
#   mac do hotkeys fix    diagnose, then offer to quit whatever is blocking them
#
# The failure looks identical from every angle: AeroSpace is running, enabled and
# has its bindings; Karabiner is grabbing; AltTab is up — and option+2 still types
# "™". The cause is almost never any of them. It is macOS Secure Input, or a
# process tapping the keyboard in front of everyone else. Neither shows up in any
# application's own logs, and both are one lookup.
set -uo pipefail
ROOT="${0:A:h:h}"
action="${1:-}"

print -r -- ""
print -r -- "  1. Secure Input — blocks every shortcut on the machine"
zsh "$ROOT/recipes/support/secure-input.zsh"
rc=$?

print -r -- "  2. Processes tapping the keyboard"
print -r -- ""
zsh "$ROOT/recipes/support/keyboard-taps.zsh" 2>/dev/null || print -r -- "    (probe unavailable)"
print -r -- ""
print -r -- "    CONSUMES means it can swallow a key before anything else sees it."
print -r -- ""

print -r -- "  3. AeroSpace"
print -r -- ""
if pgrep -qx AeroSpace; then
    printf '    running    pid %s, up %s\n' "$(pgrep -x AeroSpace)" "$(ps -o etime= -p "$(pgrep -x AeroSpace)" | xargs)"
    printf '    workspace  %s (mode %s)\n' \
        "$(/opt/homebrew/bin/aerospace list-workspaces --focused 2>/dev/null)" \
        "$(/opt/homebrew/bin/aerospace list-modes --current 2>/dev/null)"
    printf '    alt-N keys %s bound in the live config\n' \
        "$(/opt/homebrew/bin/aerospace config --get "mode.$(/opt/homebrew/bin/aerospace list-modes --current 2>/dev/null).binding" --keys 2>/dev/null | grep -cE '^alt-[0-9]$')"
else
    print -r -- "    NOT RUNNING — run: mac workspace up"
fi
print -r -- ""

(( rc == 0 )) && exit 0
[[ "$action" == fix ]] || {
    print -r -- "  ${C_DIM:-}mac do hotkeys fix   offer to quit whatever is holding it${C_RESET:-}"
    print -r -- ""
    exit $rc
}

# Only the owner of a Secure Input claim can release it, so there is nothing to
# do but quit the app — which is the user's call, never ours.
state=$("$HOME/.local/state/mac_setup/cache/secure-input-state" 2>/dev/null)
[[ "$state" == "ON" ]] || exit 0
pid=$(ioreg -l -w 0 2>/dev/null | LC_ALL=C sed -n 's/.*"kCGSSessionSecureInputPID"=\([0-9]*\).*/\1/p' | head -1)
name=$(ps -p "$pid" -o comm= 2>/dev/null | sed 's|.*/||')
if [[ -z "$name" ]]; then
    print -r -- "  The holder has already exited and the count leaked — log out and back in."
    print -r -- ""
    exit 1
fi
print -r -- "  ${name} (pid $pid) is holding Secure Input."
print -r -- ""
read -r "reply?  Quit ${name}? Unsaved work in it will be lost. [y/N] "
[[ "${reply:l}" == y* ]] || { print -r -- "  left alone"; exit 1 }
osascript -e "tell application \"${name}\" to quit" >/dev/null 2>&1
for _ in {1..20}; do
    ps -p "$pid" >/dev/null 2>&1 || break
    sleep 0.5
done
sleep 1
if [[ "$("$HOME/.local/state/mac_setup/cache/secure-input-state" 2>/dev/null)" == "OFF" ]]; then
    print -r -- "  Secure Input released — your hotkeys are back."
else
    print -r -- "  Still held. Log out and back in to clear it."
fi
print -r -- ""
