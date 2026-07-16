#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

vendor="$REPO_ROOT/vendor/AeroSpace"
stamp="$REPO_ROOT/.aerospace-build-stamp"
head="$(git -C "$vendor" rev-parse HEAD 2>/dev/null || echo none)"

if xcodebuild -version >/dev/null 2>&1; then
    if [[ ! -d /Applications/AeroSpace.app || "$head" != "$(cat "$stamp" 2>/dev/null)" ]]; then
        log "building AeroSpace from fork at $head"
        (cd "$vendor" && ./build-release.sh)
        built="$(find "$vendor/.release" -maxdepth 2 -name 'AeroSpace.app' | head -1)"
        [[ -n "$built" ]] || { warn "build finished but AeroSpace.app not found in .release"; exit 1; }
        aerospace enable off 2>/dev/null || true
        rm -rf /Applications/AeroSpace.app
        cp -R "$built" /Applications/AeroSpace.app
        echo "$head" > "$stamp"
    else
        log "AeroSpace build up to date ($head)"
    fi
else
    warn "no full Xcode — running whatever AeroSpace.app is installed (brew cask); see module 05"
fi

if [[ ! -d /Applications/AeroSpace.app ]]; then
    warn "AeroSpace.app missing — run module 10 first"
    exit 1
fi

log "launching AeroSpace"
open -g -a AeroSpace

for _ in 1 2 3 4 5; do
    if aerospace reload-config 2>/dev/null; then
        log "config loaded: $(aerospace config --config-path)"
        "$REPO_ROOT/config/aerospace/workspace-hook.sh" "$(aerospace list-workspaces --focused)"
        exit 0
    fi
    sleep 1
done
warn "AeroSpace server unreachable — grant Accessibility permission (System Settings > Privacy & Security > Accessibility: AeroSpace), then rerun module 30"
