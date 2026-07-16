#!/usr/bin/env zsh
set -euo pipefail
cd "$(dirname "$0")"

filter="${1:-}"

read -rs "SUDO_PASSWORD?sudo password: "
echo
export SUDO_PASSWORD
printf '%s\n' "$SUDO_PASSWORD" | sudo -S -v 2>/dev/null || { echo "sudo validation failed"; exit 1; }
export SUDO_ASKPASS="$(mktemp)"
trap 'rm -f "$SUDO_ASKPASS"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" "$SUDO_PASSWORD"\n' > "$SUDO_ASKPASS"
chmod 700 "$SUDO_ASKPASS"

for module in modules/[0-9]*.sh; do
    name="$(basename "$module")"
    if [[ -n "$filter" && "$name" != "$filter"* ]]; then
        continue
    fi
    echo
    echo "───────── $name ─────────"
    zsh "$module"
done

echo
echo "All done."
