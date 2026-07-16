#!/usr/bin/env zsh
# Symlink every config in config/ to its live location.
# The repo stays the single source of truth: edit here, effect is immediate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

link config/aerospace/aerospace.toml  "$HOME/.aerospace.toml"
link config/kitty/kitty.conf          "$HOME/.config/kitty/kitty.conf"
link config/karabiner/karabiner.json  "$HOME/.config/karabiner/karabiner.json"
