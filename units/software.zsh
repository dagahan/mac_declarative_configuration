requires=(base)

run homebrew why="Homebrew itself — the only thing on this machine that installs software" \
    check='command -v brew' \
    apply='zsh recipes/brew-install.zsh' \
    irreversible="removing Homebrew would take every package it installed with it"

# Everything in software.toml. A cold `brew bundle check` walks every formula
# and cask and regularly needs well over the 30s default, which used to show up
# as "unknown" and stopped the install from ever being attempted.
software all requires='run:homebrew' timeout=600

run rust-toolchain why="the Ainto core is Rust; homebrew ships only the rustup manager" \
    check='rustup show active-toolchain' \
    apply='rustup default stable' \
    revert='rustup toolchain uninstall stable; true'
