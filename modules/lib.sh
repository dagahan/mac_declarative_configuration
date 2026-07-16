export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# ${(%):-%N} = zsh for "path of the file currently being sourced"
REPO_ROOT="$(cd "$(dirname "${(%):-%N}")/.." && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }

link() {
    local src="$REPO_ROOT/$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        log "already linked: $dst"
        return 0
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        warn "backing up $dst -> $dst.pre-mac_setup"
        mv "$dst" "$dst.pre-mac_setup"
    fi
    ln -sfn "$src" "$dst"
    log "linked $dst -> $src"
}
