#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

command -v sketchybar >/dev/null || { warn "sketchybar missing — run module 10 first"; exit 1; }

log "hiding macOS menu bar"
defaults write NSGlobalDomain _HIHideMenuBar -bool true
osascript -e 'tell application "System Events" to set autohide menu bar of dock preferences to false' 2>/dev/null
osascript -e 'tell application "System Events" to set autohide menu bar of dock preferences to true'

log "starting sketchybar service"
brew services restart sketchybar >/dev/null
log "sketchybar running"
