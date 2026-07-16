#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

xcode-select -p >/dev/null 2>&1 || { log "installing Command Line Tools"; xcode-select --install; }

if xcodebuild -version >/dev/null 2>&1; then
    log "full Xcode present: $(xcodebuild -version | head -1)"
else
    warn "full Xcode missing — needed to build the AeroSpace fork (module 30 falls back to the brew cask):"
    cat <<'EOF'
      1. Install Xcode from the App Store (needs your Apple ID)
      2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
      3. sudo xcodebuild -license accept
      4. Rerun: ./sync 30
EOF
fi
