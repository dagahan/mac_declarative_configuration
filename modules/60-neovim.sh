#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Latest development build (not latest stable): official nightly release binary.
stamp="$REPO_ROOT/.nvim-nightly-stamp"
asset="nvim-macos-arm64"
prefix="$HOME/.local/opt/nvim"

latest="$(curl -sL "https://api.github.com/repos/neovim/neovim/releases/tags/nightly" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); print(next(a["updated_at"] for a in r["assets"] if a["name"]=="'"$asset"'.tar.gz"))')"

if [[ -x "$prefix/bin/nvim" && "$latest" == "$(cat "$stamp" 2>/dev/null)" ]]; then
    log "neovim nightly up to date ($("$prefix/bin/nvim" --version | head -1))"
else
    log "installing neovim nightly ($latest)"
    tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/neovim/neovim/releases/download/nightly/$asset.tar.gz" -o "$tmp/nvim.tar.gz"
    xattr -c "$tmp/nvim.tar.gz" 2>/dev/null || true
    tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
    rm -rf "$prefix"
    mkdir -p "$(dirname "$prefix")"
    mv "$tmp/$asset" "$prefix"
    rm -rf "$tmp"
    echo "$latest" > "$stamp"
    log "installed $("$prefix/bin/nvim" --version | head -1)"
fi

ln -sfn "$prefix/bin/nvim" /opt/homebrew/bin/nvim
