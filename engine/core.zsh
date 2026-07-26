typeset -gA R_PROVIDER R_UNIT R_ARGS R_ORDER
typeset -ga R_IDS U_NAMES
typeset -gA U_REQ U_OPTIN
typeset -g CURRENT_UNIT='' ARGSEP=$'\x1f'
typeset -gi REG_N=0

register() {
    local provider=$1 id=$2; shift 2
    [[ -z "${R_PROVIDER[$id]:-}" ]] || \
        die "duplicate resource '$id' (declared in ${R_UNIT[$id]} and $CURRENT_UNIT)"
    R_PROVIDER[$id]=$provider
    R_UNIT[$id]=$CURRENT_UNIT
    R_ORDER[$id]=$(( ++REG_N ))
    R_ARGS[$id]="$*"
    typeset -ga "R_ARGV_$REG_N"
    set -A "R_ARGV_$REG_N" "$@"
    R_IDS+=("$id")
}

# Fills P (key=value args) and POS (positional args) for a resource.
parse_args() {
    local id=$1 x
    local var="R_ARGV_${R_ORDER[$id]}"
    typeset -gA P; typeset -ga POS
    P=(); POS=()
    for x in "${(@P)var}"; do
        case "$x" in
            *=*) P[${x%%=*}]="${x#*=}" ;;
            *)   POS+=("$x") ;;
        esac
    done
}

# No probe may hang the tool: a check that blocks (an osascript that waits on a
# TCC prompt, a stalled daemon) is killed and reported instead of freezing.
# Timing out returns TIMED_OUT, never a plain failure — "I gave up waiting" and
# "I looked and it is wrong" are different answers, and reporting the first as
# the second makes the tool lie.
typeset -gi TIMED_OUT=124

with_timeout() {
    local secs=$1; shift
    local mark="${TMPDIR:-/tmp}/mac_setup-timeout.$$.$RANDOM"
    ( eval "$@" ) &
    local job=$!
    ( sleep "$secs"; : > "$mark"; kill -9 $job 2>/dev/null ) &
    local watcher=$!
    local rc
    wait $job 2>/dev/null; rc=$?
    kill -9 $watcher 2>/dev/null
    if [[ -e "$mark" ]]; then rm -f "$mark"; return $TIMED_OUT; fi
    return $rc
}

provider_call() {
    local verb=$1 id=$2
    local fn="${R_PROVIDER[$id]}_$verb"
    if (( ! ${+functions[$fn]} )); then
        REASON="provider '${R_PROVIDER[$id]}' cannot $verb"
        return 3
    fi
    parse_args "$id"
    $fn "$id"
}

# ── the unit DSL ──────────────────────────────────────────────────────────
run()     { register run     "run:$1"              "$@" }
pkg()     { register pkg     "pkg:$1/$2"           "$@" }
link()    { register link    "link:$2"             "$@" }
default() { register default "default:$1/$2"       "$@" }
file()    { register file    "file:$1"             "$@" }
build()   { register build   "build:$1"            "$@" }
app()     { register app     "app:$1"              "$@" }
service() { register service "service:$1"          "$@" }
daemon()  { register daemon  "daemon:$1"           "$@" }
stop()    { register stop    "stop:$1"             "$@" }
manual()  { register manual  "manual:$1"           "$@" }

# Units under private/ are always *loaded* — the engine has to know they were
# declared, or prune would offer to revert them — but a unit that sets opt_in
# is never *selected* by a bare `mac sync`. Loading and selecting are separate
# questions, and conflating them is what would tear down a working tunnel.
load_units() {
    local f unit
    for f in "$ROOT"/units/*.zsh(N) "$ROOT"/private/*/units/*.zsh(N); do
        unit="${f:t:r}"
        CURRENT_UNIT=$unit
        U_NAMES+=("$unit")
        typeset -ga requires; requires=()
        typeset -g opt_in=''
        source "$f" || die "failed to load unit $unit"
        U_REQ[$unit]="${requires[*]}"
        [[ -n "$opt_in" ]] && U_OPTIN[$unit]=1
    done
    CURRENT_UNIT=''
    unset requires opt_in
}

unit_exists() { (( ${U_NAMES[(Ie)$1]} )) }

ids_of_unit() {
    local u=$1 id
    for id in "${R_IDS[@]}"; do
        [[ "${R_UNIT[$id]}" == "$u" ]] && print -r -- "$id"
    done
}
