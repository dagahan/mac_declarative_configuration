#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log "oh-my-zsh already present"
else
    log "cloning oh-my-zsh"
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
fi
