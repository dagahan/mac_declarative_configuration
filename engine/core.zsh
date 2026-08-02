typeset -gA R_PROVIDER R_UNIT R_ARGS R_ORDER
typeset -ga R_IDS U_NAMES
typeset -gA U_REQ U_OPTIN U_WORKSPACE
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

# Writing goes through here and nowhere else, so the two rules that make a run
# interruptible cannot be forgotten by a provider author: an inverse is recorded
# before the first byte changes, and a provider with no _undo does not write at
# all. Anything left half-done is unwound by the caller, never left on disk.
provider_apply() {
    local id=$1 p="${R_PROVIDER[$id]}" rc
    if (( ! ${+functions[${p}_undo]} )); then
        REASON="provider '$p' declares no undo — refusing to write"
        return 3
    fi
    parse_args "$id"
    undo_open "${p} $(target_of "$id")"
    REASON=''
    if ! ${p}_undo "$id"; then
        REASON="${REASON:-cannot record how to undo this}"
        undo_commit
        return 3
    fi
    parse_args "$id"
    ${p}_apply "$id"; rc=$?
    return $rc
}

# Nothing a provider spawns may reach the terminal. A child that writes raw
# bytes to the tty — a dmg on stdout, a progress bar full of escapes — can
# leave it in a mode where ^C no longer interrupts anything, and then the run
# genuinely cannot be stopped. Output belongs in the journal.
#
# Backgrounded and waited on rather than run through $(...), so the pid is known
# and a cancel can end it. A terminal ^C reaches the whole foreground group and
# would have killed it anyway; a SIGINT delivered to this process alone would
# not, and then a cancelled run would sit there waiting for a command nobody can
# stop.
typeset -g SH_CHILD=''

sh_run() {
    local rc out
    out="${TMPDIR:-/tmp}/mac_run.$$.$RANDOM"
    eval "$@" >"$out" 2>&1 </dev/null &
    SH_CHILD=$!
    wait $SH_CHILD; rc=$?
    SH_CHILD=''
    LAST_OUTPUT=$(<"$out" 2>/dev/null)
    rm -f "$out"
    [[ -n "$LAST_OUTPUT" ]] && journal "$LAST_OUTPUT"
    return $rc
}

sh_kill_child() {
    [[ -n "${SH_CHILD:-}" ]] || return 0
    pkill -TERM -P "$SH_CHILD" 2>/dev/null
    kill -TERM "$SH_CHILD" 2>/dev/null
    return 0
}

# The last couple of meaningful lines, for a one-line failure reason.
sh_tail() {
    local t
    t=$(print -r -- "$LAST_OUTPUT" | grep -v '^[[:space:]]*$' | tail -2 | tr '\n' ' ')
    print -r -- "${t:-exit ${1:-1}}"
}

# ── the unit DSL ──────────────────────────────────────────────────────────
run()     { register run     "run:$1"              "$@" }
link()    { register link    "link:$2"             "$@" }
default() { register default "default:$1/$2"       "$@" }
file()    { register file    "file:$1"             "$@" }
build()   { register build   "build:$1"            "$@" }
service() { register service "service:$1"          "$@" }
daemon()  { register daemon  "daemon:$1"           "$@" }
manual()  { register manual  "manual:$1"           "$@" }

# One declaration pulls in the whole manifest: the packages as a single resource
# Homebrew converges, and every [manual.NAME] as a step of its own, so a thing
# you have to do by hand keeps its place in the order like anything else.
software() {
    register software "software:$1" "$@"
    software_load
    local n do_ url det
    for n in "${SW_MANUAL[@]}"; do
        do_=$(sw_attr manual "$n" do)
        url=$(sw_attr manual "$n" url)
        det=$(sw_attr manual "$n" detect)
        register manual "manual:$n" "$n" "do=${do_}${url:+ — $url}" ${det:+"detect=$det"}
    done
}

# A unit that sets opt_in is loaded but never *selected* by a bare `mac sync`;
# a unit that sets workspace is part of the desktop `mac workspace` owns. Both
# are properties of the unit, declared where the unit is, so adding one cannot
# require remembering to edit a list somewhere in the engine.
load_units() {
    local f unit
    for f in "$ROOT"/units/*.zsh(N) "$ROOT"/private/*/units/*.zsh(N); do
        unit="${f:t:r}"
        CURRENT_UNIT=$unit
        U_NAMES+=("$unit")
        typeset -ga requires; requires=()
        typeset -g opt_in='' workspace=''
        source "$f" || die "failed to load unit $unit"
        U_REQ[$unit]="${requires[*]}"
        [[ -n "$opt_in" ]] && U_OPTIN[$unit]=1
        [[ -n "$workspace" ]] && U_WORKSPACE[$unit]=1
    done
    CURRENT_UNIT=''
    unset requires opt_in workspace
}

unit_exists() { (( ${U_NAMES[(Ie)$1]} )) }

ids_of_unit() {
    local u=$1 id
    for id in "${R_IDS[@]}"; do
        [[ "${R_UNIT[$id]}" == "$u" ]] && print -r -- "$id"
    done
}
