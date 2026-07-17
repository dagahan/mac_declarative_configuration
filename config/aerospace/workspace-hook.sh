#!/usr/bin/env zsh
ws="${1:-$AEROSPACE_FOCUSED_WORKSPACE}"
kcli="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

if [[ "$ws" == "0" || "$ws" == "1" ]]; then
    "$kcli" --set-variables '{"aerospace_tiling":0}' 2>/dev/null
    aerospace mode floating 2>/dev/null
else
    "$kcli" --set-variables '{"aerospace_tiling":1}' 2>/dev/null
    aerospace mode main 2>/dev/null
fi
