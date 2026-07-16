#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "declaring Dock state"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.3
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock persistent-others -array

killall Dock
log "Dock restarted"
