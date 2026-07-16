#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if ! command -v brew >/dev/null; then
    log "installing Homebrew"
    # upstream installer is bash-only
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

log "brew bundle"
brew bundle --file="$REPO_ROOT/Brewfile"
