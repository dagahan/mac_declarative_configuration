#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:$PATH"

echo "$(date '+%H:%M:%S') config change detected — applying" >> /tmp/mac-setup-watch.log
aerospace reload-config 2>/dev/null
pkill -USR1 -x kitty 2>/dev/null
exit 0
