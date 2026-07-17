#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tool="$REPO_ROOT/vendor/macos_automation_scripts/redmi_pad_screenshot_to_clip_board"

command -v adb >/dev/null || { warn "adb missing — run module 10 first"; exit 1; }
[[ -d /Applications/Hammerspoon.app ]] || { warn "Hammerspoon missing — run module 10 first"; exit 1; }

log "installing redmi screenshot hotkey (ctrl+cmd+s via Hammerspoon)"
zsh "$tool/install_hotkey.sh"

if osascript -e 'tell application "System Events" to get name of every login item' 2>/dev/null | grep -q Hammerspoon; then
    log "removing Hammerspoon login item (startup happens via mac-workspace-launch)"
    osascript -e 'tell application "System Events" to delete login item "Hammerspoon"' >/dev/null
fi

cat <<'EOF'
One-time manual step (macOS requires the user):
  System Settings > Privacy & Security > Accessibility: enable Hammerspoon
  (needed for the global ctrl+cmd+s hotkey)
EOF
