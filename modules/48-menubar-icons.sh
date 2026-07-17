#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "hiding menu bar icons: AltTab, LinearMouse, Hammerspoon"
# AltTab (Defaults-backed-by-strings): this key is stored as the literal
# string "true"/"false", not a real plist boolean — a -bool write is silently
# dropped by the app on next launch.
defaults write com.lwouis.alt-tab-macos menubarIconShown -string "false"
# LinearMouse (Defaults library): JSON-encodes this enum, so the stored value
# must contain literal quote bytes around the text, not a bare word.
defaults write com.lujjjh.LinearMouse menuBarVisibilityMode -string '"never"'
defaults write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false

for app in AltTab LinearMouse Hammerspoon; do
    pgrep -qx "$app" && { pkill -x "$app"; sleep 1; }
done
open -g -a AltTab 2>/dev/null || true
open -g -a LinearMouse 2>/dev/null || true
open -g "/Applications/Hammerspoon.app" 2>/dev/null || true

pgrep -qx Karabiner-Menu && { pkill -x Karabiner-Menu; sleep 1; }
open -g "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Menu.app" 2>/dev/null || true

if [[ ! -d /Applications/Ice.app ]]; then
    warn "Ice missing — run module 10 first"
else
    log "launching Ice (covers Spotlight/Control-Center icons macOS won't let apps hide directly)"
    open -g -a Ice 2>/dev/null || true
fi

log "menu bar icons hidden (Karabiner's toggle lives in config/karabiner/karabiner.json: global.show_in_menu_bar)"
cat <<'EOF'
Two icons need a one-time manual step — their tray setting lives in a file
this script won't touch (Bitwarden's vault store, AyuGram's encrypted
session data), or macOS itself blocks scripting it (Spotlight):
  - Bitwarden > Settings > General > "Enable menu bar icon" (off)
    [already captured — see module 49]
  - AyuGram > Settings > Advanced > "Show icon in the menu bar" (off)
  - Spotlight: open Ice.app once, drag the search icon into its hidden
    section (System Settings > Control Center can't remove it; Ice can
    only cover it).
EOF
