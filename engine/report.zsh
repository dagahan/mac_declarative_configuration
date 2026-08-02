typeset -g C_RESET='' C_DIM='' C_RED='' C_GRN='' C_YEL='' C_BLU='' C_BOLD=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_BOLD=$'\033[1m'
fi

typeset -g S_OK="${C_GRN}✓${C_RESET}" S_BAD="${C_RED}✗${C_RESET}"
typeset -g S_SKIP="${C_DIM}⊘${C_RESET}" S_WARN="${C_YEL}⚠${C_RESET}" S_DOT="${C_BLU}•${C_RESET}"

say()  { print -r -- "$@" }
warn() { print -ru2 -- "${C_YEL}warning:${C_RESET} $*" }
die()  {
    print -ru2 -- "${C_RED}error:${C_RESET} $*"
    (( ${+functions[journal]} )) && { journal "FATAL $*"; journal_close 2 }
    exit 2
}
hdr()  { print -r -- ""; print -r -- "  ${C_BOLD}$*${C_RESET}" }
dim()  { print -r -- "${C_DIM}$*${C_RESET}" }

pad() { printf '%-*s' "$1" "$2" }

# For anything printed from a signal handler. A trap runs inside whatever
# command it interrupted, and inherits that command's redirections — so a ^C
# during `eval ... >/dev/null 2>&1` had its own "cancelling" message sent
# straight to /dev/null. The terminal is addressed directly instead.
tty_say() {
    if [[ -w /dev/tty ]]; then
        print -r -- "$@" > /dev/tty
    else
        print -ru2 -- "$@"
    fi
}
