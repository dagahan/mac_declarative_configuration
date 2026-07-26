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

_file_mode() { [[ -n "${P[sensitive]:-}" ]] && print -r -- 600 || print -r -- 644 }

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

file_apply() {
    local id=$1 dst tmp content
    dst=$(_file_dest)

    if [[ -n "${P[sensitive]:-}" && "${dst:A}" == "$ROOT"/* ]]; then
        REASON="a sensitive file may not live inside the repo"
        return 1
    fi

    content=$(_file_render) || return 1

    # The before-image records the destination as well as the prior state: by
    # the time we revert, the declaration is gone, so the id is all we have.
    mkdir -p "${dst:h}" || { REASON="cannot create ${dst:h}"; return 1 }
    if ! before_exists "$id"; then
        if [[ -e "$dst" ]]; then
            cp -p "$dst" "$dst.pre-mac_setup" || { REASON="cannot back up $dst"; return 1 }
            before_save "$id" "$dst"$'\t'"backup:$dst.pre-mac_setup"
        else
            before_save "$id" "$dst"$'\t'"absent"
        fi
    fi

    tmp="${dst}.mac.$$"
    print -r -- "$content" > "$tmp" || { REASON="cannot write $tmp"; return 1 }
    chmod "$(_file_mode)" "$tmp" || { REASON="chmod failed"; rm -f "$tmp"; return 1 }
    mv -f "$tmp" "$dst" || { REASON="install failed"; rm -f "$tmp"; return 1 }

    mkdir -p "$STATE/files"
    print -r -- "$(print -r -- "$content" | _file_sha) $(_file_source_fp)" > "$(_file_state "$id")"
    return 0
}

file_revert() {
    local id=$1 rec dst prev
    rec=$(before_get "$id")
    dst="${rec%%$'\t'*}"
    prev="${rec#*$'\t'}"
    [[ -n "$rec" && "$dst" != "$rec" ]] || { REASON="no record of where this file was written"; return 1 }
    rm -f "$dst"
    [[ "$prev" == backup:* && -e "${prev#backup:}" ]] && mv "${prev#backup:}" "$dst"
    rm -f "$(_file_state "$id")"
    return 0
}

file_describe() { print -r -- "${P[at]}" }
