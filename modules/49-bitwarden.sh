#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

data="$HOME/Library/Application Support/Bitwarden/data.json"
[[ -f "$data" ]] || { log "Bitwarden never launched yet — nothing to patch"; exit 0; }

log "setting Bitwarden tray icon off (trayEnabled/closeToTray)"
pgrep -qx Bitwarden && { pkill -x Bitwarden; sleep 1; }

python3 - "$data" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
d["global_desktopSettings_trayEnabled"] = False
d["global_desktopSettings_closeToTray"] = False
with open(path, "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF

open -g -a Bitwarden 2>/dev/null || true
log "Bitwarden tray icon disabled"
