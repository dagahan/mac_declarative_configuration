# apps.lock is committed: it turns rolling downloads into something a second
# machine can reproduce, and makes an upgrade a reviewable diff.
typeset -g APPS_LOCK="$ROOT/apps.lock"

lock_get() {
    python3 - "$APPS_LOCK" "$1" "$2" <<'PY'
import json, os, sys
path, name, field = sys.argv[1:4]
data = json.load(open(path)) if os.path.exists(path) else {}
print(data.get(name, {}).get(field, ""))
PY
}

lock_set() {
    python3 - "$APPS_LOCK" "$@" <<'PY'
import json, os, sys
path, name = sys.argv[1], sys.argv[2]
data = json.load(open(path)) if os.path.exists(path) else {}
entry = data.setdefault(name, {})
for pair in sys.argv[3:]:
    key, _, value = pair.partition("=")
    entry[key] = value
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

lock_drop() {
    python3 - "$APPS_LOCK" "$1" <<'PY'
import json, os, sys
path, name = sys.argv[1:3]
data = json.load(open(path)) if os.path.exists(path) else {}
data.pop(name, None)
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

# Resolves a GitHub release to "tag<TAB>asset-url".
gh_latest() {
    local repo=$1 pattern="${2:-}" tmp rc
    tmp=$(mktemp)
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$tmp" 2>/dev/null || {
        rm -f "$tmp"; return 1 }
    python3 "$ROOT/engine/gh_pick.py" "$tmp" "$pattern"
    rc=$?
    rm -f "$tmp"
    return $rc
}
