#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tool="$REPO_ROOT/vendor/macos_automation_scripts/redmi_pad_screenshot_to_clip_board"

command -v adb >/dev/null || { warn "adb missing — run module 10 first"; exit 1; }
[[ -d /Applications/Hammerspoon.app ]] || { warn "Hammerspoon missing — run module 10 first"; exit 1; }

log "installing redmi screenshot hotkey (ctrl+cmd+s via Hammerspoon)"
zsh "$tool/install_hotkey.sh"

if ! osascript -e 'tell application "System Events" to get name of every login item' 2>/dev/null | grep -q Hammerspoon; then
    log "adding Hammerspoon to login items"
    osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Hammerspoon.app", hidden:true}' >/dev/null
fi

if ! pgrep -q Hammerspoon; then
    log "launching Hammerspoon"
    open -g /Applications/Hammerspoon.app
    sleep 2
    pgrep -q Hammerspoon || warn "Hammerspoon did not start"
fi

cat <<'EOF'
One-time manual step (macOS requires the user):
  System Settings > Privacy & Security > Accessibility: enable Hammerspoon
  (needed for the global ctrl+cmd+s hotkey)
EOF
