#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ ! -d /Applications/AeroSpace.app ]]; then
    warn "AeroSpace.app missing — run module 10 first"
    exit 1
fi

log "launching AeroSpace"
open -a AeroSpace

for _ in 1 2 3 4 5; do
    if aerospace reload-config 2>/dev/null; then
        log "config loaded: $(aerospace config --config-path)"
        exit 0
    fi
    sleep 1
done
warn "AeroSpace server unreachable — grant Accessibility permission, then rerun module 30"
