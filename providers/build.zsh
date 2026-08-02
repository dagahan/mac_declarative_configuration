# A git tree id over the whole worktree — the same source always hashes the
# same, whether or not it has been committed yet. Mixing in HEAD instead made
# committing unchanged code look like a source change and forced a rebuild.
# A scratch index keeps the real one untouched; `add -A` catches new files too.
_build_tree() {
    local dir="$ROOT/$1" idx tree
    idx="${TMPDIR:-/tmp}/mac_setup-idx.$$"
    rm -f "$idx"
    tree=$( GIT_INDEX_FILE="$idx" git -C "$dir" add -A 2>/dev/null \
            && GIT_INDEX_FILE="$idx" git -C "$dir" write-tree 2>/dev/null )
    rm -f "$idx"
    [[ -n "$tree" ]] && { print -r -- "$tree"; return 0 }
    git -C "$dir" rev-parse "HEAD^{tree}" 2>/dev/null || print -r -- none
}

_build_fp() {
    local tree rec
    tree=$(_build_tree "$1")
    rec=$(shasum "$ROOT/$2" 2>/dev/null | cut -c1-12)
    print -r -- "${tree:0:12}.${rec}"
}

_build_stamp_file() { print -r -- "$STATE/builds/$1" }

build_check() {
    local name=${POS[1]} app="${P[app]}" want have
    [[ -e "$app" ]] || { REASON="not installed"; return 1 }
    want=$(_build_fp "${P[from]}" "${P[recipe]}")
    have=$(cat "$(_build_stamp_file "$name")" 2>/dev/null)
    [[ "$want" == "$have" ]] && return 0
    if [[ -z "$have" ]]; then REASON="never built by mac"; else REASON="source or recipe changed"; fi
    return 1
}

# The installed copy is renamed aside, never deleted, so an interrupted install
# is one rename away from the bundle that was working ten seconds ago. Both
# moves are renames within a filesystem: there is no window where neither the
# old nor the new bundle is in place.
_build_install() {
    local src=$1 app=$2 proc=$3 sign=$4
    _svc_stop "$proc"
    rm -rf "$app.new"
    ditto "$src" "$app.new" || { REASON="ditto failed"; return 1 }
    [[ "$sign" == 1 ]] && { codesign -f -s mac-setup-codesign --deep "$app.new" 2>/dev/null || { REASON="codesign failed"; rm -rf "$app.new"; return 1 } }
    rm -rf "$app.mac-prev"
    [[ -e "$app" ]] && { mv "$app" "$app.mac-prev" || { REASON="cannot move the installed copy aside"; return 1 } }
    mv "$app.new" "$app" || { REASON="install swap failed"; return 1 }
    return 0
}

build_undo() {
    local id=$1 name=${POS[1]} app="${P[app]}" stamp blob
    stamp=$(_build_stamp_file "$name")
    undo_push "restore $app" \
        "rm -rf ${(q)app}.new; if [[ -e ${(q)app}.mac-prev ]]; then rm -rf ${(q)app}; mv ${(q)app}.mac-prev ${(q)app}; fi"
    if [[ -e "$stamp" ]] && blob=$(undo_backup "$stamp"); then
        undo_push "restore build stamp for $name" "cp -p ${(q)blob} ${(q)stamp}"
    else
        undo_push "clear build stamp for $name" "rm -f ${(q)stamp}"
    fi
    return 0
}

build_apply() {
    local name=${POS[1]} app="${P[app]}" proc="${P[proc]:-${POS[1]}}"
    local dir="$ROOT/${P[from]}" recipe="$ROOT/${P[recipe]}"
    local sign="${P[sign]:-1}" fp cache art log rc
    fp=$(_build_fp "${P[from]}" "${P[recipe]}")
    cache="$STATE/artifacts/$name/$fp.app"
    mkdir -p "$STATE/builds" "$STATE/artifacts/$name"

    if [[ -d "$cache" ]]; then
        _build_install "$cache" "$app" "$proc" 0 || return 1
    else
        log="$STATE/journal/build-$name.log"
        export BUILD_DIR="$dir" BUILD_NAME="$name" BUILD_REF="${fp%%.*}"
        ( zsh "$recipe" > "$log" 2>&1 </dev/null ); rc=$?
        if (( rc != 0 )); then REASON="build failed — see $log"; return 1; fi
        art="$dir/${P[artifact]}"
        [[ -e "$art" ]] || { REASON="build produced no ${P[artifact]}"; return 1 }
        _build_install "$art" "$app" "$proc" "$sign" || return 1
        ditto "$app" "$cache" 2>/dev/null
        # A leftover build product shares the bundle id with the installed copy;
        # LaunchServices and TCC then flip-flop and permission grants never stick.
        rm -rf "$art"
    fi

    local pair
    for pair in ${=P[also]:-}; do
        cp -f "$dir/${pair%%:*}" "${pair##*:}" || { REASON="failed to install ${pair##*:}"; return 1 }
    done

    print -r -- "$fp" > "$(_build_stamp_file "$name")"
    _build_prune_cache "$name"
    rm -rf "$app.mac-prev"
    needs_restart "$proc"
    REASON=''
    return 0
}

_build_prune_cache() {
    local dir="$STATE/artifacts/$1" old
    for old in $(ls -td "$dir"/*.app(N) 2>/dev/null | tail -n +4); do rm -rf "$old"; done
}

build_describe() { print -r -- "${POS[1]}" }
