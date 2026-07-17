#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "declaring Dock state"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000
defaults write com.apple.dock autohide-time-modifier -float 0.3
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock persistent-others -array

log "disabling Dock jump/bounce animations"
defaults write com.apple.dock launchanim -bool false
defaults write com.apple.dock mineffect -string "scale"
defaults write com.apple.dock expose-animation-duration -float 0
defaults write com.apple.dock no-bouncing -bool true
log "Dock state declared (restart happens in workspace-launch)"
