requires=(ohmyzsh)

run dotfiles why="symlink config/ into place" \
    check=always apply='zsh modules/20-dotfiles.sh'
