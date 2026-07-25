requires=(base)

run homebrew why="Homebrew itself" \
    check='command -v brew' \
    apply='zsh recipes/brew-install.zsh'

run brewfile why="every package declared in the Brewfile" \
    check='brew bundle check --file=Brewfile' \
    apply='brew bundle --file=Brewfile'

run rust-toolchain why="the Ainto core is Rust; homebrew ships only the rustup manager" \
    check='rustup show active-toolchain' \
    apply='rustup default stable'
