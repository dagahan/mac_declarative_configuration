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

log "launching Karabiner-Elements (it picks up the linked karabiner.json)"
open -a Karabiner-Elements

cat <<'EOF'
One-time manual steps (macOS requires the user to do these, see README):
  1. System Settings -> Privacy & Security: allow the Karabiner driver extension.
  2. System Settings -> Privacy & Security -> Input Monitoring: enable both
     karabiner_grabber and karabiner_observer.
EOF
