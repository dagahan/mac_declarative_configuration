#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Official TLauncher bootstrap jar wrapped in a minimal .app; the bootstrap
# self-updates the real launcher, so a one-time install is enough.
app="/Applications/TLauncher.app"
java="/opt/homebrew/opt/openjdk@17/bin/java"

if [[ -f "$app/Contents/Resources/TLauncher.jar" ]]; then
    log "TLauncher already installed"
    exit 0
fi

[[ -x "$java" ]] || warn "openjdk@17 not found at $java (brew module installs it)"

log "installing TLauncher bootstrap from llaun.ch"
tmp="$(mktemp -d)"
curl -fsSL "https://llaun.ch/jar" -o "$tmp/TLauncher.jar"
unzip -tq "$tmp/TLauncher.jar" >/dev/null || { warn "downloaded TLauncher.jar is not a valid jar"; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mv "$tmp/TLauncher.jar" "$app/Contents/Resources/TLauncher.jar"
rm -rf "$tmp"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TLauncher</string>
    <key>CFBundleIdentifier</key><string>org.tlauncher.bootstrap</string>
    <key>CFBundleName</key><string>TLauncher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
PLIST

cat > "$app/Contents/MacOS/TLauncher" <<SH
#!/bin/zsh
exec "$java" -jar "$app/Contents/Resources/TLauncher.jar"
SH
chmod +x "$app/Contents/MacOS/TLauncher"
log "installed TLauncher.app"
