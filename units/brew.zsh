requires=(base)

run homebrew why="Homebrew itself" \
    check='command -v brew' \
    apply='zsh recipes/brew-install.zsh'

# A cold `brew bundle check` walks every formula and cask and regularly needs
# well over the 30s default, which showed up as "unknown" and stopped the
# install from ever being attempted.
run brewfile why="every package declared in the Brewfile" \
    check='brew bundle check --file=Brewfile' \
    apply='brew bundle --file=Brewfile' timeout=300

run rust-toolchain why="the Ainto core is Rust; homebrew ships only the rustup manager" \
    check='rustup show active-toolchain' \
    apply='rustup default stable'
