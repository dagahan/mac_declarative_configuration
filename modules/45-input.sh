#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "key repeat: fast"
defaults write -g KeyRepeat -int 2
defaults write -g InitialKeyRepeat -int 15

log "trackpad: three-finger swipe up (Mission Control) off"
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 0
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture -int 0
defaults write com.apple.dock showMissionControlGestureEnabled -bool false
log "re-login required for key repeat to fully apply"
