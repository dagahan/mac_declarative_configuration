requires=(brew dotfiles)

run karabiner why="activate driver extension, verify key grabbing" \
    check=always apply='zsh modules/50-keyboard.sh'
