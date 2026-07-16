#!/usr/bin/env zsh
if [[ "$1" == "$FOCUSED_WORKSPACE" ]]; then
    sketchybar --set "$NAME" background.drawing=on label.color=0xff11111b
else
    sketchybar --set "$NAME" background.drawing=off label.color=0xffcdd6f4
fi
