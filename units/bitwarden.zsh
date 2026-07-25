requires=(brew)

stop Bitwarden before='run:bitwarden-tray'

run bitwarden-tray why="tray icon lives in Bitwarden's own data.json, not in defaults" \
    check='zsh recipes/bitwarden-tray.zsh check' \
    apply='zsh recipes/bitwarden-tray.zsh apply'
