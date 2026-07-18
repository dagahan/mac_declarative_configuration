#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"
vendor="$REPO_ROOT/vendor/AeroSpace"
stamp="$REPO_ROOT/.aerospace-build-stamp"
head="$(git -C "$vendor" rev-parse HEAD 2>/dev/null || echo none)"

if [[ -d /Applications/Xcode.app ]]; then
    if [[ ! -d /Applications/AeroSpace.app || "$head" != "$(cat "$stamp" 2>/dev/null)" ]]; then
        log "building AeroSpace from fork at ${head:0:8} (log: /tmp/aerospace-build.log)"
        (cd "$vendor" \
            && ./generate.sh --codesign-identity - \
            && swift build -c release --arch arm64 --product aerospace \
            && xcodebuild -project xcode/AeroSpace.xcodeproj -scheme AeroSpace -configuration Release -derivedDataPath .xcbuild build
        ) > /tmp/aerospace-build.log 2>&1 || { warn "build failed — see /tmp/aerospace-build.log"; exit 1; }
        app="$vendor/.xcbuild/Build/Products/Release/AeroSpace.app"
        cli="$vendor/.build/arm64-apple-macosx/release/aerospace"
        [[ -d "$app" && -x "$cli" ]] || { warn "build artifacts missing"; exit 1; }
        brew list --cask aerospace >/dev/null 2>&1 && brew uninstall --cask aerospace >/dev/null
        pkill -x AeroSpace 2>/dev/null || true
        rm -rf /Applications/AeroSpace.app
        ditto "$app" /Applications/AeroSpace.app
        codesign -f -s mac-setup-codesign --deep /Applications/AeroSpace.app
        cp -f "$cli" /opt/homebrew/bin/aerospace
        # A leftover build-product .app shares the bundle id with the installed copy;
        # LaunchServices/TCC then flip-flop between them and permission grants never stick.
        rm -rf "$app"
        echo "$head" > "$stamp"
        log "installed fork build (app + cli)"
    else
        log "AeroSpace build up to date (${head:0:8})"
    fi
else
    warn "no Xcode — using existing AeroSpace.app; see module 05"
fi

[[ -d /Applications/AeroSpace.app ]] || { warn "AeroSpace.app missing"; exit 1; }
