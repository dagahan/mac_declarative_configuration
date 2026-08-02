# macOS lies about prefs in two directions: cfprefsd caches reads, and some apps
# store booleans as strings. Every quirk lives here, once, instead of in units.
typeset -gA DOMAIN_APP=(
    com.apple.dock                    Dock
    com.apple.finder                  Finder
    com.lwouis.alt-tab-macos          AltTab
    com.lujjjh.LinearMouse            LinearMouse
    org.hammerspoon.Hammerspoon       Hammerspoon
    app.ainto.macos                   Ainto
)

_def_read() { defaults read "$1" "$2" 2>/dev/null }

_def_type() { defaults read-type "$1" "$2" 2>/dev/null | sed 's/^Type is //' }

_def_norm() {
    local t=$1 v=$2
    case $t in
        bool)  case "${v:l}" in 1|true|yes) print -r -- 1 ;; *) print -r -- 0 ;; esac ;;
        int)   print -r -- "${v//[^0-9-]/}" ;;
        float) printf '%g\n' "$v" 2>/dev/null || print -r -- "$v" ;;
        # Swift-based apps (Ainto) rewrite strings with \uXXXX escapes on quit;
        # comparing raw bytes would report eternal drift and restart them forever.
        *)     if [[ "$v" == *'\u'* ]]; then print -r -- "${(g::)v}"; else print -r -- "$v"; fi ;;
    esac
}

_def_write() {
    local domain=$1 key=$2 type=$3 want=$4
    case $type in
        array)  defaults write "$domain" "$key" -array ;;
        bool)   defaults write "$domain" "$key" -bool "$want" ;;
        int)    defaults write "$domain" "$key" -int "$want" ;;
        float)  defaults write "$domain" "$key" -float "$want" ;;
        string) defaults write "$domain" "$key" -string "$want" ;;
        raw)    defaults write "$domain" "$key" "$want" ;;
        *)      REASON="unknown type '$type'"; return 1 ;;
    esac
}

default_check() {
    local id=$1 domain=${POS[1]} key=${POS[2]} type=${POS[3]} want="${POS[4]:-}"
    local cur rc
    cur=$(_def_read "$domain" "$key"); rc=$?
    if [[ "$type" == array ]]; then
        (( rc == 0 )) || { REASON="unset → empty array"; return 1 }
        [[ "${cur//[[:space:]]/}" == "()" ]] && return 0
        REASON="has entries → empty array"
        return 1
    fi
    if (( rc != 0 )); then REASON="unset → $want"; return 1; fi
    [[ "$(_def_norm "$type" "$cur")" == "$(_def_norm "$type" "$want")" ]] && return 0
    REASON="$cur → $want"
    return 1
}

# The value as it stands right now, as a command that would put it back. Written
# through read-type rather than the declared type, because what the machine holds
# and what the repo wants are not always the same shape.
default_undo() {
    local id=$1 domain=${POS[1]} key=${POS[2]} cur t
    if cur=$(_def_read "$domain" "$key"); then
        t=$(_def_type "$domain" "$key")
        case $t in
            boolean) undo_push "restore $domain $key" \
                        "defaults write ${(q)domain} ${(q)key} -bool $( [[ "$cur" == 1 ]] && print true || print false )" ;;
            integer) undo_push "restore $domain $key" "defaults write ${(q)domain} ${(q)key} -int ${(q)cur}" ;;
            float)   undo_push "restore $domain $key" "defaults write ${(q)domain} ${(q)key} -float ${(q)cur}" ;;
            # Arrays and dictionaries round-trip through their plist text.
            *)       undo_push "restore $domain $key" "defaults write ${(q)domain} ${(q)key} ${(q)cur}" ;;
        esac
    else
        undo_push "unset $domain $key" "defaults delete ${(q)domain} ${(q)key} 2>/dev/null; true"
    fi
    return 0
}

default_apply() {
    local id=$1 domain=${POS[1]} key=${POS[2]} type=${POS[3]} want="${POS[4]:-}"
    local app
    stop_owner || return 1
    if ! _def_write "$domain" "$key" "$type" "$want"; then
        REASON="${REASON:-defaults write failed}"
        return 1
    fi

    if ! default_check "$id"; then
        sleep 0.4
        if ! default_check "$id"; then REASON="write did not stick ($REASON)"; return 1; fi
    fi
    REASON=''
    app="${P[affects]:-${P[stop_app]:-${DOMAIN_APP[$domain]:-}}}"
    [[ -n "$app" ]] && needs_restart "$app"
    return 0
}

# The off state is declared, never inferred. Reading the machine's value at first
# apply and calling that "the original" was a fiction: whichever sync happened to
# run first decided it, and for most keys no such record was ever written, so a
# revert silently became a delete. `on_workspace_down=` says what off means, in
# the repo, where it can be reviewed.
default_down() {
    local id=$1 domain=${POS[1]} key=${POS[2]} type=${POS[3]}
    local want="${P[on_workspace_down]:-}" app
    [[ -n "$want" ]] || { REASON="no on_workspace_down= declared"; return 1 }
    if [[ "$want" == delete ]]; then
        defaults delete "$domain" "$key" 2>/dev/null
    else
        if ! _def_write "$domain" "$key" "$type" "$want"; then
            REASON="${REASON:-defaults write failed}"
            return 1
        fi
    fi
    app="${P[affects]:-${P[stop_app]:-${DOMAIN_APP[$domain]:-}}}"
    [[ -n "$app" ]] && needs_restart "$app"
    REASON=''
    return 0
}

default_revert() { default_down "$@" }

default_describe() { print -r -- "${POS[1]} ${POS[2]}" }
