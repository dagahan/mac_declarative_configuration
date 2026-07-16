#!/usr/bin/env zsh
pct="$(pmset -g batt | grep -Eo '[0-9]+%' | head -1)"
charging=""
pmset -g batt | grep -q 'AC Power' && charging="⚡"
sketchybar --set "$NAME" label="${charging}${pct}"
