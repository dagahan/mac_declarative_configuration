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

_def_parts() {
    local rest=${1#default:}
    typeset -g DEF_DOMAIN=${rest%%/*} DEF_KEY=${rest#*/}
}

_def_read() { defaults read "$1" "$2" 2>/dev/null }

_def_norm() {
    local t=$1 v=$2
    case $t in
        bool)  case "${v:l}" in 1|true|yes) print -r -- 1 ;; *) print -r -- 0 ;; esac ;;
        int)   print -r -- "${v//[^0-9-]/}" ;;
        float) printf '%g\n' "$v" 2>/dev/null || print -r -- "$v" ;;
        *)     print -r -- "$v" ;;
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

default_apply() {
    local id=$1 domain=${POS[1]} key=${POS[2]} type=${POS[3]} want="${POS[4]:-}"
    local cur rc app
    cur=$(_def_read "$domain" "$key"); rc=$?
    (( rc == 0 )) || cur='<absent>'
    before_save "$id" "$type"$'\n'"$cur"

    case $type in
        array)  defaults write "$domain" "$key" -array ;;
        bool)   defaults write "$domain" "$key" -bool "$want" ;;
        int)    defaults write "$domain" "$key" -int "$want" ;;
        float)  defaults write "$domain" "$key" -float "$want" ;;
        string) defaults write "$domain" "$key" -string "$want" ;;
        raw)    defaults write "$domain" "$key" "$want" ;;
        *)      REASON="unknown type '$type'"; return 1 ;;
    esac
    if (( $? != 0 )); then REASON="defaults write failed"; return 1; fi

    if ! default_check "$id"; then
        sleep 0.4
        if ! default_check "$id"; then REASON="write did not stick ($REASON)"; return 1; fi
    fi
    REASON=''
    app="${P[affects]:-${DOMAIN_APP[$domain]:-}}"
    [[ -n "$app" ]] && needs_restart "$app"
    return 0
}

default_revert() {
    local id=$1 prev type value app
    _def_parts "$id"
    prev=$(before_get "$id")
    type="${prev%%$'\n'*}"
    value="${prev#*$'\n'}"
    if [[ -z "$prev" || "$value" == '<absent>' ]]; then
        defaults delete "$DEF_DOMAIN" "$DEF_KEY" 2>/dev/null
    else
        case $type in
            bool)   defaults write "$DEF_DOMAIN" "$DEF_KEY" -bool "$value" ;;
            int)    defaults write "$DEF_DOMAIN" "$DEF_KEY" -int "$value" ;;
            float)  defaults write "$DEF_DOMAIN" "$DEF_KEY" -float "$value" ;;
            *)      defaults write "$DEF_DOMAIN" "$DEF_KEY" -string "$value" ;;
        esac
    fi
    app="${DOMAIN_APP[$DEF_DOMAIN]:-}"
    [[ -n "$app" ]] && needs_restart "$app"
    return 0
}

default_describe() { print -r -- "${POS[1]} ${POS[2]}" }
