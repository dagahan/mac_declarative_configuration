# Secrets live in the repo as age ciphertext; only the key that opens them
# lives in Bitwarden. age is asymmetric, so the public half — committed as
# unlock-key.public — is enough to *add* a secret. Nothing is ever unlocked to
# write one, and `mac check` never unlocks anything either (see providers/file.zsh).
# The vault is touched once per machine, the first time something must be read.

typeset -g SECRETS_DIR="$ROOT/config/secrets"
typeset -g SECRETS_PUB="$SECRETS_DIR/unlock-key.public"
typeset -g SECRETS_BW="$SECRETS_DIR/bitwarden.conf"
typeset -g IDENTITY="$HOME/.config/mac_setup/age.key"
typeset -gA SECRET_CACHE

secret_file()    { print -r -- "$SECRETS_DIR/$1.locked" }
secret_exists()  { [[ -f "$(secret_file "$1")" ]] }
secret_have_id() { [[ -f "$IDENTITY" ]] }

_secret_bw_item() {
    [[ -f "$SECRETS_BW" ]] && sed -n 's/^ *item *= *//p' "$SECRETS_BW" | head -1
}

_secret_bw_status() {
    bw status 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null
}

# The one moment the vault is needed. It explains itself, because otherwise it
# is a password prompt appearing in the middle of an unrelated command.
secret_unlock() {
    secret_have_id && return 0
    local item; item=$(_secret_bw_item)
    [[ -n "$item" ]] || { REASON="no Bitwarden item configured in config/secrets/bitwarden.conf"; return 1 }

    print -r -- ""
    print -r -- "  ${C_BOLD}This machine can't read your secrets yet.${C_RESET}"
    dim  "    They are encrypted in the repo; the key that opens them is in Bitwarden."
    dim  "    Item: \"$item\"    ·    Asked once per machine, never again."
    print -r -- ""

    command -v bw >/dev/null || { REASON="bitwarden-cli not installed — run: mac sync brew"; return 1 }

    local status; status=$(_secret_bw_status)
    if [[ "$status" == unauthenticated ]]; then
        bw login || { REASON="bitwarden login failed"; return 1 }
        status=$(_secret_bw_status)
    fi

    local session
    if [[ "$status" != unlocked ]]; then
        session=$(bw unlock --raw) || { REASON="bitwarden unlock failed"; return 1 }
    else
        session="${BW_SESSION:-}"
    fi

    bw sync --session "$session" >/dev/null 2>&1
    mkdir -p "${IDENTITY:h}"
    local tmp="${IDENTITY}.tmp.$$"
    if ! bw get notes "$item" --session "$session" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"; REASON="could not read \"$item\" from Bitwarden"; return 1
    fi
    grep -q '^AGE-SECRET-KEY-' "$tmp" || {
        rm -f "$tmp"; REASON="\"$item\" does not contain an age key"; return 1
    }
    chmod 600 "$tmp"; mv -f "$tmp" "$IDENTITY"
    print -r -- "  $S_OK got it — this machine won't ask again"
    print -r -- ""
    return 0
}

# Called by providers/file.zsh while rendering a template.
secret_value() {
    local name=$1
    [[ -n "${SECRET_CACHE[$name]:-}" ]] && { print -r -- "${SECRET_CACHE[$name]}"; return 0 }
    secret_exists "$name" || return 1
    secret_unlock || return 1
    local val
    val=$(age -d -i "$IDENTITY" "$(secret_file "$name")" 2>/dev/null) || return 1
    SECRET_CACHE[$name]="$val"
    print -r -- "$val"
}

_secret_keygen() {
    mkdir -p "$SECRETS_DIR" "${IDENTITY:h}"
    age-keygen -o "$IDENTITY" 2>/dev/null || return 1
    chmod 600 "$IDENTITY"
    age-keygen -y "$IDENTITY" > "$SECRETS_PUB" || return 1
    print -r -- ""
    print -r -- "  $S_OK generated a new unlock key"
    dim  "    public half committed to ${SECRETS_PUB#$ROOT/}"
    print -r -- ""
    print -r -- "  ${C_BOLD}Save it in Bitwarden now — this is the only copy:${C_RESET}"
    dim  "    item name: $(_secret_bw_item)      field: note"
    print -r -- ""
    print -r -- "    open -e $IDENTITY"
    print -r -- ""
    # Deliberately not printed. A key echoed to a terminal ends up in scrollback,
    # tmux buffers, CI logs and screen recordings — places it can never be
    # withdrawn from. Reading the file is the user's decision, not ours.
    dim  "    (not shown here on purpose — copy the AGE-SECRET-KEY line from that file)"
    print -r -- ""
}

cmd_secret() {
    local action=${1:-list}; shift 2>/dev/null
    case "$action" in
        add|set)
            local name=$1
            [[ -n "$name" ]] || die "usage: mac secret add <name>"
            [[ -f "$SECRETS_PUB" ]] || _secret_keygen || die "could not generate an unlock key"
            local value
            if [[ ! -t 0 ]]; then
                value=$(cat)
            else
                print -n "  value for '$name' (hidden): "
                read -rs value; print -r -- ""
            fi
            [[ -n "$value" ]] || die "empty value"
            mkdir -p "$SECRETS_DIR"
            print -r -- "$value" | age -a -R "$SECRETS_PUB" > "$(secret_file "$name")" \
                || die "encryption failed"
            print -r -- "  $S_OK locked ${$(secret_file "$name")#$ROOT/}"
            dim  "    commit it — the value itself never leaves this machine in the clear"
            ;;
        get)
            local name=$1
            [[ -n "$name" ]] || die "usage: mac secret get <name>"
            secret_exists "$name" || die "no such secret: $name"
            secret_value "$name" || die "${REASON:-could not decrypt $name}"
            ;;
        list)
            local f name
            [[ -d "$SECRETS_DIR" ]] || { print -r -- "  no secrets yet"; return 0 }
            print -r -- ""
            for f in "$SECRETS_DIR"/*.locked(N); do
                name="${${f:t}%.locked}"
                printf '    %-24s %s\n' "$name" "$(shasum -a 256 "$f" | cut -c1-12)"
            done
            print -r -- ""
            dim "    unlock key on this machine: $(secret_have_id && print -n 'present' || print -n 'not yet fetched')"
            ;;
        rotate)
            [[ -d "$SECRETS_DIR" ]] || die "no secrets to rotate"
            secret_unlock || die "${REASON:-need the current key to re-encrypt}"
            local -a names; local f name val
            for f in "$SECRETS_DIR"/*.locked(N); do names+=("${${f:t}%.locked}"); done
            typeset -A vals
            for name in "${names[@]}"; do
                vals[$name]=$(age -d -i "$IDENTITY" "$(secret_file "$name")") || die "cannot decrypt $name"
            done
            rm -f "$IDENTITY"
            _secret_keygen || die "keygen failed"
            for name in "${names[@]}"; do
                print -r -- "${vals[$name]}" | age -a -R "$SECRETS_PUB" > "$(secret_file "$name")"
            done
            print -r -- "  $S_OK re-encrypted ${#names} secret(s) — commit, and update Bitwarden"
            ;;
        unlock) secret_unlock || die "${REASON:-unlock failed}" ;;
        *) die "usage: mac secret <add|get|list|rotate|unlock>" ;;
    esac
}
