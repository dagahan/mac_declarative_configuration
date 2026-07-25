requires=(base)

run brew why="Homebrew install + Brewfile bundle" \
    check=always apply='zsh modules/10-brew.sh'
