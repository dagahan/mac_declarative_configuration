requires=()

run requirements why="Xcode CLT, Rosetta, mac-setup-codesign cert, Rust toolchain" \
    check=always apply='zsh modules/05-requirements.sh'
