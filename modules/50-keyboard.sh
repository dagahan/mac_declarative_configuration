#!/usr/bin/env zsh
# Key remapping via Karabiner-Elements.
# The actual rules live in config/karabiner/karabiner.json (linked by module 20):
#   - Cmd+Tab -> vk_none  (kills the macOS app switcher; workspaces replace it)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ ! -d "/Applications/Karabiner-Elements.app" ]]; then
    warn "Karabiner-Elements missing — run module 10 (brew) first"
    exit 1
fi

log "Karabiner-Elements installed; it reads the linked karabiner.json"

cat <<'EOF'
One-time manual steps (macOS requires the user to do these, see README):
  1. Open Karabiner-Elements once yourself — its background services register
     on first launch (no window is opened by this script on purpose).
  2. System Settings -> Privacy & Security: allow the Karabiner driver extension.
  3. System Settings -> Privacy & Security -> Input Monitoring: enable both
     karabiner_grabber and karabiner_observer.
EOF
