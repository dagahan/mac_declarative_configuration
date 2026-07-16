# Shared helpers, sourced by every module. Not executable on its own.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }

# link <repo-relative-source> <absolute-target>
# Symlinks a config file into place. A pre-existing real file is backed up
# next to itself as <name>.pre-mac_setup so nothing is ever destroyed.
link() {
    local src="$REPO_ROOT/$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        log "already linked: $dst"
        return 0
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        warn "backing up existing $dst -> $dst.pre-mac_setup"
        mv "$dst" "$dst.pre-mac_setup"
    fi
    ln -sfn "$src" "$dst"
    log "linked $dst -> $src"
}
