import json
import sys

path = sys.argv[1]
pattern = sys.argv[2] if len(sys.argv) > 2 else ""

try:
    release = json.load(open(path))
except Exception:
    sys.exit(1)

assets = release.get("assets", [])
if pattern:
    assets = [a for a in assets if pattern.lower() in a["name"].lower()] or assets

preferred = (".dmg", ".pkg", ".zip", ".tar.gz")
assets.sort(key=lambda a: next(
    (i for i, ext in enumerate(preferred) if a["name"].lower().endswith(ext)), len(preferred)))

if not assets:
    sys.exit(1)

print(release.get("tag_name", "") + "\t" + assets[0]["browser_download_url"])
