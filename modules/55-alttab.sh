#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# defaults read prints the stored cmd symbol either raw or unicode-escaped
is_cmd() { [[ "$1" == "⌘" || "$1" == *u2318* ]] }

if [[ ! -d "/Applications/AltTab.app" ]]; then
    warn "AltTab missing — run module 10 first"
    exit 1
fi

current="$(defaults read com.lwouis.alt-tab-macos holdShortcut 2>/dev/null || echo none)"
if ! is_cmd "$current"; then
    if pgrep -q AltTab; then
        osascript -e 'quit app "AltTab"' 2>/dev/null || pkill AltTab
        sleep 2
    fi
    log "AltTab: setting Cmd+Tab trigger"
    defaults write com.lwouis.alt-tab-macos holdShortcut -string "⌘"
    is_cmd "$(defaults read com.lwouis.alt-tab-macos holdShortcut)" || { warn "trigger write did not stick"; exit 1; }
fi

if ! pgrep -q AltTab; then
    log "launching AltTab"
    open -g -a AltTab
    sleep 2
    pgrep -q AltTab || warn "AltTab did not start — open it once manually and grant Accessibility + Screen Recording"
fi
log "AltTab on Cmd+Tab, running"
