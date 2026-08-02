requires=(software)

# Bitwarden rewrites data.json on quit, so it has to be down while this changes.
run bitwarden-tray why="tray icon lives in Bitwarden's own data.json, not in defaults" \
    check='zsh recipes/bitwarden-tray.zsh check' \
    apply='zsh recipes/bitwarden-tray.zsh apply' \
    stop_app=Bitwarden \
    irreversible="the tray preference lives in Bitwarden's own store, which it rewrites on every quit"
