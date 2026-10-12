set -euo pipefail
state="$HOME/Library/Application Support/Yandex/YandexBrowser/Local State"
[[ -e "$state" ]] || exit 0
python3 -I - "$state" "$1" <<'PY'
import json, sys
path, verb = sys.argv[1], sys.argv[2]
d = json.load(open(path))
shot = d.setdefault("ya", {}).setdefault("screenshoter", {})
if verb == "check":
    sys.exit(0 if shot.get("hotkeys_enabled") is False else 1)
shot["hotkeys_enabled"] = verb == "on"
json.dump(d, open(path, "w"), separators=(",", ":"))
PY
