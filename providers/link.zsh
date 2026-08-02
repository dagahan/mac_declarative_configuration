link_check() {
    local src="$ROOT/${POS[1]}" dst="${POS[2]}"
    if [[ -L "$dst" ]]; then
        [[ "$(readlink "$dst")" == "$src" ]] && return 0
        REASON="→ $(readlink "$dst")"
        return 1
    fi
    if [[ -e "$dst" ]]; then REASON="real file in the way"; return 1; fi
    REASON="missing"
    return 1
}

link_undo() {
    local id=$1 dst prev blob
    dst="${POS[2]}"
    if [[ -L "$dst" ]]; then
        prev=$(readlink "$dst")
        undo_push "relink $dst" "ln -sfn ${(q)prev} ${(q)dst}"
    elif [[ -e "$dst" ]]; then
        blob=$(undo_backup "$dst") || { REASON="cannot copy $dst aside"; return 1 }
        undo_push "restore $dst" "rm -rf ${(q)dst}; cp -pR ${(q)blob} ${(q)dst}"
    else
        undo_push "remove $dst" "rm -f ${(q)dst}"
    fi
    return 0
}

link_apply() {
    local id=$1 src="$ROOT/${POS[1]}" dst="${POS[2]}"
    [[ -e "$src" ]] || { REASON="source missing: ${POS[1]}"; return 1 }
    stop_owner || return 1
    mkdir -p "${dst:h}"
    # A real file in the way is moved aside rather than destroyed; undo_backup
    # already holds a copy, so this only keeps the original out of the symlink's
    # path without a second full copy.
    [[ -e "$dst" && ! -L "$dst" ]] && { mv "$dst" "$dst.pre-mac_setup" || { REASON="cannot move $dst aside"; return 1 } }
    ln -sfn "$src" "$dst" || { REASON="symlink failed"; return 1 }
    return 0
}

link_describe() { print -r -- "${POS[2]}" }
