#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "hiding menu bar icons: AltTab, LinearMouse"
defaults write com.lwouis.alt-tab-macos menubarIconShown -bool false
defaults write com.lujjjh.LinearMouse showInMenuBar -bool false
defaults write com.lujjjh.LinearMouse menuBarVisibilityMode -string "never"

for app in AltTab LinearMouse; do
    pgrep -qx "$app" && { pkill -x "$app"; sleep 1; }
    open -g -a "$app" 2>/dev/null || true
done

pgrep -qx Karabiner-Menu && { pkill -x Karabiner-Menu; sleep 1; }
open -g "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Menu.app" 2>/dev/null || true

log "menu bar icons hidden (Karabiner's own icon toggle lives in config/karabiner/karabiner.json: global.show_in_menu_bar)"
cat <<'EOF'
Bitwarden's "show icon in menu bar" is not scripted here on purpose: it's
stored inside data.json alongside your encrypted vault state, and this
setup avoids writing to that file. Toggle it off once yourself in
Bitwarden > Settings.
EOF
