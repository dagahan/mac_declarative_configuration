requires=(base brew)

run alttab why="build AltTab fork, install app" \
    check=always apply='zsh modules/55-alttab.sh'
