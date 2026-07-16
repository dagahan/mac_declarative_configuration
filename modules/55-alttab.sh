#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ ! -d "/Applications/AltTab.app" ]]; then
    warn "AltTab missing — run module 10 first"
    exit 1
fi

current="$(defaults read com.lwouis.alt-tab-macos holdShortcut 2>/dev/null || echo none)"
if [[ "$current" != "⌘" ]]; then
    pgrep -q AltTab && { pkill AltTab; sleep 1; }
    log "AltTab: setting Cmd+Tab trigger"
    defaults write com.lwouis.alt-tab-macos holdShortcut -string "⌘"
fi

if ! pgrep -q AltTab; then
    log "launching AltTab"
    open -g -a AltTab
    sleep 2
    pgrep -q AltTab || warn "AltTab did not start — open it once manually and grant Accessibility + Screen Recording"
fi
