# Writes a config file the repo owns. A `.tmpl` source has {{placeholders}}
# filled in from secrets; anything else is copied verbatim.
#
# `sensitive` changes how the file is judged, not just its mode. Checking a
# normal file re-renders it and compares content. Doing that to a secret file
# would mean decrypting on every `mac check` — so instead we remember two
# fingerprints and compare those: the file we wrote, and the *ciphertext* it
# came from. The ciphertext changes whenever the secret does, so a changed
# declaration is still detected without ever unlocking anything.

_file_dest() {
    local d="${P[at]}"
    print -r -- "${d/#\~/$HOME}"
}

_file_mode() {
    [[ -n "${P[mode]:-}" ]] && { print -r -- "${P[mode]}"; return }
    [[ -n "${P[sensitive]:-}" ]] && print -r -- 600 || print -r -- 644
}

_file_state() {
    local key="${1//[^a-zA-Z0-9._-]/_}"
    print -r -- "$STATE/files/$key"
}

_file_placeholders() {
    grep -o '{{[a-zA-Z0-9_-]\{1,\}}}' "$1" 2>/dev/null | sort -u
}

_file_value() {
    (( ${+functions[secret_value]} )) || return 1
    secret_value "$1"
}

# Every secret the template names, hashed as ciphertext. Never decrypts.
_file_source_fp() {
    local src="$ROOT/${P[from]}" ph name
    {
        shasum -a 256 "$src" 2>/dev/null
        for ph in ${(f)"$(_file_placeholders "$src")"}; do
            name="${${ph#\{\{}%\}\}}"
            shasum -a 256 "$ROOT/config/secrets/$name.locked" 2>/dev/null
        done
    } | shasum -a 256 | cut -d' ' -f1
}

_file_render() {
    local src="$ROOT/${P[from]}" content ph name val
    [[ -e "$src" ]] || { REASON="source missing: ${P[from]}"; return 1 }
    if [[ "$src" != *.tmpl ]]; then cat "$src"; return 0; fi
    content=$(<"$src")
    for ph in ${(f)"$(_file_placeholders "$src")"}; do
        name="${${ph#\{\{}%\}\}}"
        val=$(_file_value "$name") || { REASON="no value for $ph"; return 1 }
        content="${content//"$ph"/$val}"
    done
    print -r -- "$content"
}

_file_sha() { shasum -a 256 | cut -d' ' -f1 }

file_check() {
    local id=$1 dst want have
    dst=$(_file_dest)
    [[ -e "$dst" ]] || { REASON="missing"; return 1 }

    local mode; mode=$(stat -f '%Lp' "$dst" 2>/dev/null)
    if [[ "$mode" != "$(_file_mode)" ]]; then
        REASON="mode $mode, want $(_file_mode)"
        return 1
    fi

    have=$(_file_sha < "$dst")

    if [[ -n "${P[sensitive]:-}" ]]; then
        local rec; rec=$(cat "$(_file_state "$id")" 2>/dev/null)
        [[ -n "$rec" ]] || { REASON="never written by mac"; return 1 }
        local rec_dst="${rec%% *}" rec_src="${rec##* }"
        [[ "$have" == "$rec_dst" ]] || { REASON="edited outside mac_setup"; return 1 }
        [[ "$(_file_source_fp)" == "$rec_src" ]] || { REASON="template or secret changed"; return 1 }
        return 0
    fi

    want=$(_file_render) || return 1
    [[ "$(print -r -- "$want" | _file_sha)" == "$have" ]] && return 0
    REASON="content differs"
    return 1
}

file_undo() {
    local id=$1 dst st blob sudo_=''
    dst=$(_file_dest); st=$(_file_state "$id")
    [[ -n "${P[root]:-}" ]] && sudo_='sudo -n '
    if [[ -e "$dst" ]]; then
        blob=$(undo_backup "$dst") || { REASON="cannot copy $dst aside"; return 1 }
        undo_push "restore $dst" "${sudo_}cp -p ${(q)blob} ${(q)dst}"
    else
        undo_push "remove $dst" "${sudo_}rm -f ${(q)dst}"
    fi
    if [[ -e "$st" ]] && blob=$(undo_backup "$st"); then
        undo_push "restore fingerprint of ${dst:t}" "cp -p ${(q)blob} ${(q)st}"
    else
        undo_push "clear fingerprint of ${dst:t}" "rm -f ${(q)st}"
    fi
    return 0
}

file_apply() {
    local id=$1 dst tmp content
    dst=$(_file_dest)

    if [[ -n "${P[sensitive]:-}" && "${dst:A}" == "$ROOT"/* ]]; then
        REASON="a sensitive file may not live inside the repo"
        return 1
    fi

    content=$(_file_render) || return 1

    [[ -n "${P[root]:-}" ]] || mkdir -p "${dst:h}" || { REASON="cannot create ${dst:h}"; return 1 }

    # Staged beside the destination and renamed into place: a rename is atomic,
    # so an interrupted write can never be observed as a truncated config. root=
    # is for the few places only root may write, /Library/LaunchDaemons above all.
    tmp="${TMPDIR:-/tmp}/mac_file.$$"
    print -r -- "$content" > "$tmp" || { REASON="cannot write $tmp"; return 1 }
    chmod "$(_file_mode)" "$tmp" || { REASON="chmod failed"; rm -f "$tmp"; return 1 }
    if [[ -n "${P[root]:-}" ]]; then
        if ! sudo -n true 2>/dev/null; then
            rm -f "$tmp"; REASON="root access expired mid-run"; return 1
        fi
        sudo -n mkdir -p "${dst:h}" && sudo -n cp "$tmp" "$dst.mac-new" \
            && sudo -n chown root:wheel "$dst.mac-new" && sudo -n chmod "$(_file_mode)" "$dst.mac-new" \
            && sudo -n mv -f "$dst.mac-new" "$dst" \
            || { rm -f "$tmp"; sudo -n rm -f "$dst.mac-new" 2>/dev/null; REASON="root install failed"; return 1 }
        rm -f "$tmp"
    else
        mv -f "$tmp" "$dst" || { REASON="install failed"; rm -f "$tmp"; return 1 }
    fi

    mkdir -p "$STATE/files"
    print -r -- "$(print -r -- "$content" | _file_sha) $(_file_source_fp)" > "$(_file_state "$id")"
    return 0
}

file_describe() { print -r -- "${P[at]}" }
