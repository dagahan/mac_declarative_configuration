"""Normalized keys for every app Homebrew installs.

Casks that ship a .pkg (Office, Google Drive, Hamachi, Karabiner) declare no
"app" artifact at all, so the cask token and display name are matched too.
"""
import json
import re
import subprocess
import sys


def key(text):
    return re.sub(r"[^a-z0-9]", "", text.lower().removesuffix(".app"))


casks = subprocess.run(["brew", "list", "--cask"], capture_output=True, text=True).stdout.split()
if not casks:
    sys.exit(0)

info = subprocess.run(["brew", "info", "--cask", "--json=v2"] + casks,
                      capture_output=True, text=True).stdout
try:
    data = json.loads(info)
except Exception:
    sys.exit(0)

keys = set()
for cask in data.get("casks", []):
    keys.add(key(cask.get("token", "")))
    for name in cask.get("name", []) or []:
        keys.add(key(name))
    for artifact in cask.get("artifacts", []):
        if not isinstance(artifact, dict):
            continue
        for entry in artifact.get("app", []) or []:
            if isinstance(entry, str):
                keys.add(key(entry.split("/")[-1]))
        for section in ("uninstall", "zap"):
            for step in artifact.get(section, []) or []:
                if not isinstance(step, dict):
                    continue
                for field in ("delete", "trash"):
                    value = step.get(field) or []
                    for path in ([value] if isinstance(value, str) else value):
                        if isinstance(path, str) and path.endswith(".app"):
                            keys.add(key(path.split("/")[-1]))

for k in sorted(k for k in keys if k):
    print(k)
