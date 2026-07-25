typeset -gA R_PROVIDER R_UNIT R_ARGS R_ORDER
typeset -ga R_IDS U_NAMES
typeset -gA U_REQ
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
stop()    { register stop    "stop:$1"             "$@" }
manual()  { register manual  "manual:$1"           "$@" }

load_units() {
    local f unit
    for f in "$ROOT"/units/*.zsh(N) "$ROOT"/apps/external.zsh(N); do
        unit="${f:t:r}"
        CURRENT_UNIT=$unit
        U_NAMES+=("$unit")
        typeset -ga requires; requires=()
        source "$f" || die "failed to load unit $unit"
        U_REQ[$unit]="${requires[*]}"
    done
    CURRENT_UNIT=''
    unset requires
}

unit_exists() { (( ${U_NAMES[(Ie)$1]} )) }

ids_of_unit() {
    local u=$1 id
    for id in "${R_IDS[@]}"; do
        [[ "${R_UNIT[$id]}" == "$u" ]] && print -r -- "$id"
    done
}
