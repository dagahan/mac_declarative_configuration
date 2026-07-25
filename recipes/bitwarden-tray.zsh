data="$HOME/Library/Application Support/Bitwarden/data.json"
[[ -f "$data" ]] || exit 0   # never launched: nothing to patch, nothing drifting

python3 - "$data" "${1:-check}" <<'PY'
import json, sys
path, mode = sys.argv[1], sys.argv[2]
keys = ("global_desktopSettings_trayEnabled", "global_desktopSettings_closeToTray")
with open(path) as f:
    data = json.load(f)
if mode == "check":
    sys.exit(0 if all(data.get(k) is False for k in keys) else 1)
for k in keys:
    data[k] = False
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
