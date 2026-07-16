#!/usr/bin/env bash
# Activate AeroSpace and load the repo config.
#
# Today this uses the upstream cask from the Brewfile. When the fork in
# vendor/AeroSpace diverges, build it from source instead:
#   cd vendor/AeroSpace && ./build-release.sh   (needs full Xcode)
# then install the produced .app and remove the cask from the Brewfile.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ ! -d /Applications/AeroSpace.app ]]; then
    warn "AeroSpace.app missing — run module 10 (brew) first"
    exit 1
fi

log "launching AeroSpace"
open -a AeroSpace

# Give the server a moment on first launch, then load the repo config.
for _ in 1 2 3 4 5; do
    if aerospace reload-config 2>/dev/null; then
        log "config loaded: $(aerospace config --config-path)"
        exit 0
    fi
    sleep 1
done
warn "could not reach the AeroSpace server — grant Accessibility permission, then rerun this module"
