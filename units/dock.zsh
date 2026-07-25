requires=()

run dock why="Dock autohide, empty persistent apps, no bounce" \
    check=always apply='zsh modules/40-dock.sh'
