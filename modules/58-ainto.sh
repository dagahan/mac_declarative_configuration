#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"
vendor="$REPO_ROOT/vendor/ainto-app"
stamp="$REPO_ROOT/.ainto-build-stamp"
head="$(git -C "$vendor" rev-parse HEAD 2>/dev/null || echo none)"

# Real cargo/rustc live in the active rustup toolchain; put them on PATH so the
# Rust core links (homebrew's rustup doesn't create ~/.cargo/bin proxies).
if command -v rustup >/dev/null 2>&1; then
    tc="$(rustup show active-toolchain 2>/dev/null | awk '{print $1}')"
    [[ -n "$tc" ]] && export PATH="$HOME/.rustup/toolchains/$tc/bin:$PATH"
fi

if [[ ! -d /Applications/Xcode.app ]]; then
    warn "no Xcode — cannot build Ainto launcher; see module 05"
    return 0 2>/dev/null || exit 0
fi
if ! command -v cargo >/dev/null 2>&1; then
    warn "cargo not found — install Rust (module 05 runs 'rustup default stable')"
    return 0 2>/dev/null || exit 0
fi

if [[ -d /Applications/Ainto.app && "$head" == "$(cat "$stamp" 2>/dev/null)" ]]; then
    log "Ainto build up to date (${head:0:8})"
else
    log "building Ainto from fork at ${head:0:8} (log: /tmp/ainto-build.log)"
    (cd "$vendor" \
        && cargo build --release --manifest-path ainto-core/Cargo.toml \
        && cd AintoApp \
        && xcodegen generate \
        && xcodebuild -scheme AintoApp -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    ) > /tmp/ainto-build.log 2>&1 || { warn "build failed — see /tmp/ainto-build.log"; exit 1; }
    app="$vendor/AintoApp/build/Build/Products/Release/Ainto.app"
    [[ -d "$app" ]] || { warn "build artifact missing"; exit 1; }
    pkill -x Ainto 2>/dev/null || true
    rm -rf /Applications/Ainto.app
    ditto "$app" /Applications/Ainto.app
    codesign -f -s mac-setup-codesign --deep /Applications/Ainto.app
    # Drop the build product so it can't shadow the installed copy for LaunchServices/TCC.
    rm -rf "$app"
    echo "$head" > "$stamp"
    touch /tmp/mac-setup-relaunch-Ainto
    log "installed Ainto launcher (app)"
fi

[[ -d /Applications/Ainto.app ]] || { warn "Ainto.app missing"; exit 1; }

# --- Declarative launcher prefs (applied whether or not a rebuild happened) ---

# Ainto's global hotkey is stored in UserDefaults, not its TOML. Keep it on its
# default Cmd+Shift+Space (no Spotlight conflict). Karabiner remaps Cmd+Space ->
# Cmd+Shift+Space (config/karabiner/karabiner.json), intercepting Cmd+Space at the
# driver level before Spotlight sees it — so Cmd+Space opens Ainto with no system
# setting changes and no logout. (Written while Ainto is stopped so it isn't flushed
# back on quit.)
pgrep -qx Ainto && { pkill -x Ainto; sleep 1; }
defaults write app.ainto.macos globalHotkey "⌘ ⇧ Space"

# Undo any earlier attempt to disable Spotlight's Cmd+Space symbolic hotkey (id 64):
# the Karabiner interception makes that unnecessary, so leave Spotlight at default.
plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
if [[ "$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" "$plist" 2>/dev/null)" =~ ^(false|0)$ ]]; then
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
        '{ enabled = 1; value = { parameters = (32, 49, 1048576); type = standard; }; }'
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
fi
