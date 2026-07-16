#!/usr/bin/env bash
# mac_setup — one-shot, idempotent installer.
# Usage:
#   ./install.sh              run every module in order
#   ./install.sh 40           run only module(s) whose number matches
set -euo pipefail
cd "$(dirname "$0")"

filter="${1:-}"

for module in modules/[0-9]*.sh; do
    name="$(basename "$module")"
    if [[ -n "$filter" && "$name" != "$filter"* ]]; then
        continue
    fi
    echo
    echo "───────── $name ─────────"
    bash "$module"
done

echo
echo "All done. Check README.md → 'Manual post-install steps' for the one-time permission grants."
