requires=()

run hiddify why="Hiddify from GitHub releases (becomes an app resource in phase 4)" \
    check=always apply='zsh modules/70-hiddify.sh'
