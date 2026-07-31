#!/usr/bin/env zsh
# Compiles once into the state dir, then just runs.
set -uo pipefail
SRC="${0:A:h}/keyboard-taps.swift"
BIN="${XDG_STATE_HOME:-$HOME/.local/state}/mac_setup/cache/keyboard-taps"
mkdir -p "${BIN:h}"
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
    swiftc -O -o "$BIN" "$SRC" 2>/dev/null || { print -ru2 -- "cannot build the tap probe"; exit 1 }
fi
exec "$BIN"
