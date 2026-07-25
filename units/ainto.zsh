requires=(base brew)

run ainto why="build Ainto launcher fork, install app, set hotkey" \
    check=always apply='zsh modules/58-ainto.sh'
