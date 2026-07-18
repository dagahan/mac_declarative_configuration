#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "declaring menu bar icon + autostart prefs: AltTab, LinearMouse, Hammerspoon"
# Apps are stopped first so they can't flush stale cached prefs over these
# writes on their next quit; workspace-launch starts them again at the end
# of sync.
for app in AltTab LinearMouse Hammerspoon; do
    pgrep -qx "$app" && { pkill -x "$app"; sleep 1; }
done

# AltTab stores booleans as literal strings; a -bool write is discarded on launch.
defaults write com.lwouis.alt-tab-macos menubarIconShown -string "false"
defaults write com.lwouis.alt-tab-macos startAtLogin -string "false"
# ShowHowPreference raw index: 1 = hide (ghost windowless apps otherwise show on every workspace)
defaults write com.lwouis.alt-tab-macos showWindowlessApps -string "1"
# LinearMouse JSON-encodes this enum: the value must contain literal quote bytes.
defaults write com.lujjjh.LinearMouse menuBarVisibilityMode -string '"never"'
defaults write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false

pgrep -qx Karabiner-Menu && { pkill -x Karabiner-Menu; sleep 1; }

cat <<'EOF'
Two icons need a one-time manual step — their setting lives in a file this
script won't touch (Bitwarden's vault store is handled by module 49;
AyuGram's lives in encrypted session data):
  - AyuGram > Settings > Advanced > "Show icon in the menu bar" (off)
Spotlight's menu-bar icon cannot be hidden by any script or app since
macOS Mojave — it's compiled into the system.
EOF