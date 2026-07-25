requires=()

run ohmyzsh why="oh-my-zsh framework clone" \
    check='[[ -d $HOME/.oh-my-zsh ]]' apply='zsh modules/15-ohmyzsh.sh'
