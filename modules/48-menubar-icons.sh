#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "hiding menu bar icons: AltTab, LinearMouse, Spotlight"
defaults write com.lwouis.alt-tab-macos menubarIconShown -bool false
# LinearMouse (Defaults library) JSON-encodes this enum: the stored value must
# be the literal 3 characters "never" wrapped in real quote bytes, not a bare word.
defaults write com.lujjjh.LinearMouse menuBarVisibilityMode -string '"never"'
defaults write com.apple.Spotlight "NSStatusItem VisibleCC Item-0" -bool false

for app in AltTab LinearMouse; do
    pgrep -qx "$app" && { pkill -x "$app"; sleep 1; }
    open -g -a "$app" 2>/dev/null || true
done

pgrep -qx Karabiner-Menu && { pkill -x Karabiner-Menu; sleep 1; }
open -g "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Menu.app" 2>/dev/null || true

killall SystemUIServer 2>/dev/null || true
killall ControlCenter 2>/dev/null || true

log "menu bar icons hidden (Karabiner's toggle lives in config/karabiner/karabiner.json: global.show_in_menu_bar)"
cat <<'EOF'
Bitwarden's tray icon has no persisted setting on disk yet (not even a
default), so it can't be scripted here. Toggle it off yourself once:
  Bitwarden > Settings > General > "Enable menu bar icon"
Once you do, its state lands in data.json and can be pinned declaratively.
EOF
