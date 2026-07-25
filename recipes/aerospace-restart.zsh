export PATH="/opt/homebrew/bin:$PATH"
prev="$(aerospace list-workspaces --focused 2>/dev/null | head -1)"

pkill -x AeroSpace 2>/dev/null
for _ in {1..50}; do pgrep -qx AeroSpace || break; sleep 0.2; done
pgrep -qx AeroSpace && { pkill -9 -x AeroSpace; sleep 0.5; }

open -g /Applications/AeroSpace.app
for _ in {1..12}; do aerospace list-workspaces --focused >/dev/null 2>&1 && break; sleep 1; done
aerospace list-workspaces --focused >/dev/null 2>&1 || {
    print -ru2 -- "AeroSpace server unreachable — grant Accessibility, then rerun"
    exit 1
}
if [[ -n "$prev" && "$(aerospace list-workspaces --focused 2>/dev/null | head -1)" != "$prev" ]]; then
    aerospace workspace "$prev" 2>/dev/null
fi
