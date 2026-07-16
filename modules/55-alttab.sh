#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ ! -d "/Applications/AltTab.app" ]]; then
    warn "AltTab missing — run module 10 first"
    exit 1
fi

log "AltTab: Cmd+Tab trigger, start at login"
defaults write com.lwouis.alt-tab-macos holdShortcut -string "⌘"
defaults write com.lwouis.alt-tab-macos startAtLogin -bool true

if ! pgrep -q AltTab; then
    cat <<'EOF'
One-time manual steps for AltTab:
  1. Open AltTab.app once yourself (no window is opened by this script on purpose).
  2. Grant the two permissions it asks for:
     System Settings > Privacy & Security > Accessibility:     AltTab
     System Settings > Privacy & Security > Screen Recording:  AltTab (for window previews)
EOF
fi
