# Two edge sets on purpose: E_ORDER decides sequencing, E_DEP decides blame.
# A failed resource only skips what genuinely depends on it, never everything
# that merely happens to run after it.
typeset -gA E_ORDER E_DEP
typeset -ga ORDERED

_edge() {
    local from=$1 to=$2 map=$3
    [[ "$from" == "$to" ]] && return
    case $map in
        order) [[ " ${E_ORDER[$from]:-} " == *" $to "* ]] || E_ORDER[$from]="${E_ORDER[$from]:-} $to" ;;
        dep)   [[ " ${E_DEP[$from]:-} "   == *" $to "* ]] || E_DEP[$from]="${E_DEP[$from]:-} $to" ;;
    esac
}

add_order() { _edge "$1" "$2" order }
add_dep()   { _edge "$1" "$2" order; _edge "$1" "$2" dep }

build_graph() {
    local id prev='' unit dep did
    E_ORDER=(); E_DEP=()

    for id in "${R_IDS[@]}"; do
        if [[ -n "$prev" && "${R_UNIT[$prev]}" == "${R_UNIT[$id]}" ]]; then
            add_order "$prev" "$id"
        fi
        prev=$id
    done

    for id in "${R_IDS[@]}"; do
        unit=${R_UNIT[$id]}
        for dep in ${=U_REQ[$unit]:-}; do
            unit_exists "$dep" || die "unit '$unit' requires unknown unit '$dep'"
            for did in $(ids_of_unit "$dep"); do add_dep "$did" "$id"; done
        done
    done

    for id in "${R_IDS[@]}"; do
        parse_args "$id"
        if [[ -n "${P[requires]:-}" ]]; then
            for dep in ${=P[requires]}; do
                if unit_exists "$dep"; then
                    for did in $(ids_of_unit "$dep"); do add_dep "$did" "$id"; done
                elif [[ -n "${R_PROVIDER[$dep]:-}" ]]; then
                    add_dep "$dep" "$id"
                else
                    die "resource '$id' requires unknown '$dep'"
                fi
            done
        fi
        if [[ -n "${P[before]:-}" ]]; then
            for did in "${R_IDS[@]}"; do
                [[ "$did" == ${~P[before]} ]] && add_order "$id" "$did"
            done
        fi
        if [[ -n "${P[after]:-}" ]]; then
            for did in "${R_IDS[@]}"; do
                [[ "$did" == ${~P[after]} ]] && add_order "$did" "$id"
            done
        fi
    done
}

topo() {
    local -A indeg
    local -a queue
    local id t best i
    for id in "${R_IDS[@]}"; do indeg[$id]=0; done
    for id in "${R_IDS[@]}"; do
        for t in ${=E_ORDER[$id]:-}; do (( indeg[$t]++ )); done
    done
    for id in "${R_IDS[@]}"; do (( indeg[$id] == 0 )) && queue+=("$id"); done
    ORDERED=()
    while (( ${#queue} )); do
        best=1
        for (( i = 2; i <= ${#queue}; i++ )); do
            (( R_ORDER[${queue[i]}] < R_ORDER[${queue[best]}] )) && best=$i
        done
        id=${queue[best]}; queue[best]=()
        ORDERED+=("$id")
        for t in ${=E_ORDER[$id]:-}; do
            (( --indeg[$t] == 0 )) && queue+=("$t")
        done
    done
    if (( ${#ORDERED} != ${#R_IDS} )); then
        local -a stuck
        for id in "${R_IDS[@]}"; do
            (( ${ORDERED[(Ie)$id]} )) || stuck+=("$id")
        done
        die "dependency cycle among: ${stuck[*]}"
    fi
}

propagate_skip() {
    local root=$1 from=$2 t
    for t in ${=E_DEP[$from]:-}; do
        [[ -n "${SKIP[$t]:-}" ]] && continue
        SKIP[$t]=$root
        propagate_skip "$root" "$t"
    done
}
