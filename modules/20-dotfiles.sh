#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

link config/zsh/.zprofile             "$HOME/.zprofile"
link config/zsh/.zshrc                "$HOME/.zshrc"
link config/aerospace/aerospace.toml  "$HOME/.aerospace.toml"
link config/kitty/kitty.conf          "$HOME/.config/kitty/kitty.conf"
link config/karabiner/karabiner.json  "$HOME/.config/karabiner/karabiner.json"
link config/linearmouse/linearmouse.json "$HOME/.config/linearmouse/linearmouse.json"
