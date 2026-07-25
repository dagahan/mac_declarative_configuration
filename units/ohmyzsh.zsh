requires=()

run ohmyzsh why="the zsh framework .zshrc sources; nothing else provides it" \
    check='[[ -d "$HOME/.oh-my-zsh" ]]' \
    apply='zsh recipes/ohmyzsh.zsh'
