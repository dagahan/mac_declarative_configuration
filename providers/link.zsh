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

link_apply() {
    local id=$1 src="$ROOT/${POS[1]}" dst="${POS[2]}"
    [[ -e "$src" ]] || { REASON="source missing: ${POS[1]}"; return 1 }
    mkdir -p "${dst:h}"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        mv "$dst" "$dst.pre-mac_setup" || { REASON="cannot back up $dst"; return 1 }
        placement_save "$id" "backup:$dst.pre-mac_setup"
    else
        placement_exists "$id" || placement_save "$id" "absent"
    fi
    ln -sfn "$src" "$dst" || { REASON="symlink failed"; return 1 }
    return 0
}

link_revert() {
    # Separate statements: in zsh a later assignment in the same `local` cannot
    # see an earlier one, so `local id=$1 dst="${id#link:}"` leaves dst empty.
    local id=$1 prev dst
    dst="${id#link:}"
    prev=$(placement_get "$id")
    [[ -L "$dst" ]] && rm -f "$dst"
    [[ "$prev" == backup:* && -e "${prev#backup:}" ]] && mv "${prev#backup:}" "$dst"
    return 0
}

link_describe() { print -r -- "${POS[2]}" }
