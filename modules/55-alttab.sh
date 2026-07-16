#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ ! -d "/Applications/AltTab.app" ]]; then
    warn "AltTab missing — run module 10 first"
    exit 1
fi

if ! pgrep -q AltTab; then
    log "launching AltTab"
    open -g -a AltTab
    sleep 2
fi

# shortcuts are stored as NSKeyedArchiver blobs; only AltTab itself (or our
# fork's changed default) can write them
if ! python3 -c "
import subprocess, plistlib, sys
d = plistlib.loads(subprocess.run(['defaults','export','com.lwouis.alt-tab-macos','-'],capture_output=True).stdout)
sys.exit(0 if '⌘' in str(d.get('holdShortcut','')) else 1)"; then
    warn "AltTab trigger is not Cmd+Tab yet — one-time manual step:"
    echo "      AltTab settings > Controls > Shortcut 1 > Hold: change ⌥ to ⌘"
    echo "      (permanent fix ships with the fork build: default changed in source)"
fi
