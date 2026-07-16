#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

driver_manager="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
core_log="/var/log/karabiner/core_service.log"

if [[ ! -d "/Applications/Karabiner-Elements.app" ]]; then
    warn "Karabiner-Elements missing — run module 10 first"
    exit 1
fi

log "activating Karabiner driver extension"
"$driver_manager" activate >/dev/null 2>&1

log "starting Karabiner services"
open -g -j -a Karabiner-Elements
sleep 4

if grep -q "monitor is started (grabbed)" "$core_log" 2>/dev/null; then
    log "Karabiner is grabbing the keyboard — Cmd+Tab remap live"
else
    warn "Karabiner isn't intercepting keys yet. Grant these once (Karabiner 16 layout):"
    cat <<'EOF'
      System Settings > General > Login Items & Extensions
        Driver Extensions:      enable  .Karabiner-VirtualHIDDevice-Manager
        App Background Activity: enable  Karabiner-Elements Non-Privileged Agents v2
                                 enable  Karabiner-Elements Privileged Daemons v2
      System Settings > Privacy & Security > Accessibility
                                 enable  Karabiner-Core-Service
    Then rerun: ./sync 50
EOF
fi
