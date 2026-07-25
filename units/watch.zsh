requires=(dotfiles)

run watch why="launchd WatchPaths agent on config/ (removed in phase 5)" \
    check=always apply='zsh modules/25-watch.sh'
