requires=(base brew dotfiles)

run aerospace why="build AeroSpace fork, install app + cli" \
    check=always apply='zsh modules/30-aerospace.sh'
