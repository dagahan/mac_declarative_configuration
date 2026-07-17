#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

repo="hiddify/hiddify-app"
stamp="$REPO_ROOT/.hiddify-version-stamp"
latest_tag="$(curl -sL "https://api.github.com/repos/$repo/releases/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"

if [[ -d /Applications/Hiddify.app && "$latest_tag" == "$(cat "$stamp" 2>/dev/null)" ]]; then
    log "Hiddify up to date ($latest_tag)"
else
    log "installing Hiddify $latest_tag from GitHub releases (hiddify-app, official repo)"
    dmg_url="https://github.com/$repo/releases/download/$latest_tag/Hiddify-MacOS.dmg"
    tmp="$(mktemp -d)"
    curl -fsSL "$dmg_url" -o "$tmp/Hiddify.dmg"
    mount_point="$tmp/mnt"
    mkdir -p "$mount_point"
    hdiutil attach "$tmp/Hiddify.dmg" -mountpoint "$mount_point" -nobrowse -quiet
    app="$(find "$mount_point" -maxdepth 1 -name '*.app' | head -1)"
    [[ -n "$app" ]] || { warn "no .app found in Hiddify dmg"; hdiutil detach "$mount_point" -quiet; exit 1; }
    pkill -x Hiddify 2>/dev/null || true
    rm -rf /Applications/Hiddify.app
    ditto "$app" /Applications/Hiddify.app
    hdiutil detach "$mount_point" -quiet
    rm -rf "$tmp"
    echo "$latest_tag" > "$stamp"
    log "installed Hiddify $latest_tag"
fi
