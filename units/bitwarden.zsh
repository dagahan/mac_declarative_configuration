requires=(brew)

run bitwarden why="tray icon off in Bitwarden data.json" \
    check=always apply='zsh modules/49-bitwarden.sh'
