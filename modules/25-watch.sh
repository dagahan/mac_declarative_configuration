#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

label="com.mac-setup.config-watch"
plist="$HOME/Library/LaunchAgents/$label.plist"

watch_keys=""
for d in "$REPO_ROOT"/config/*(/); do
    watch_keys+="        <string>$d</string>
"
done

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$REPO_ROOT/config/watch/apply.sh</string>
    </array>
    <key>WatchPaths</key>
    <array>
$watch_keys    </array>
    <key>ThrottleInterval</key>
    <integer>2</integer>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
log "config watcher active (launchd WatchPaths on config/*)"
