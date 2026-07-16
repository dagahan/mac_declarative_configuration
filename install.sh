#!/usr/bin/env zsh
# mac_setup — one-shot, idempotent installer.
# Usage:
#   ./install.sh              run every module in order
#   ./install.sh 40           run only module(s) whose number matches
set -euo pipefail
cd "$(dirname "$0")"

filter="${1:-}"

# One sudo prompt up front; a background loop keeps the ticket fresh so any
# later sudo (e.g. cask pkg installers) runs without asking again.
# The password itself is only ever seen by sudo — never stored anywhere.
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
trap 'kill %1 2>/dev/null' EXIT

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
