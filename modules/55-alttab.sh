#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
vendor="$REPO_ROOT/vendor/alt-tab-macos"
stamp="$REPO_ROOT/.alttab-build-stamp"
head="$(git -C "$vendor" rev-parse HEAD 2>/dev/null || echo none)"

if [[ -d /Applications/Xcode.app ]]; then
    if [[ "$head" != "$(cat "$stamp" 2>/dev/null)" || ! -d /Applications/AltTab.app ]]; then
        log "building AltTab from fork at ${head:0:8} (log: /tmp/alttab-build.log)"
        (cd "$vendor" \
            && xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData CURRENT_PROJECT_VERSION="11.4.3-${head:0:8}" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build \
            && codesign -f -s - --deep DerivedData/Build/Products/Release/AltTab.app
        ) > /tmp/alttab-build.log 2>&1 || { warn "build failed — see /tmp/alttab-build.log"; exit 1; }
        app="$vendor/DerivedData/Build/Products/Release/AltTab.app"
        [[ -d "$app" ]] || { warn "build artifact missing"; exit 1; }
        brew list --cask alt-tab >/dev/null 2>&1 && brew uninstall --cask alt-tab >/dev/null
        pkill -x AltTab 2>/dev/null || true
        rm -rf /Applications/AltTab.app
        ditto "$app" /Applications/AltTab.app
        echo "$head" > "$stamp"
        log "installed fork build"
        warn "ad-hoc signature changed — re-grant Accessibility + Screen Recording to AltTab when macOS asks"
    else
        log "AltTab build up to date (${head:0:8})"
    fi
else
    warn "no Xcode — using existing AltTab.app; see module 05"
fi

if [[ ! -d /Applications/AltTab.app ]]; then
    warn "AltTab.app missing"
    exit 1
fi

if ! pgrep -q AltTab; then
    log "launching AltTab"
    open -g -a AltTab
    sleep 2
    pgrep -q AltTab || warn "AltTab did not start — open it once manually and grant permissions"
fi
