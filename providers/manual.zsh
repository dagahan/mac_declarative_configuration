# A step the machine cannot take for itself: a permission granted in System
# Settings, a licensed installer fetched by hand, a checkbox inside an app.
# It never applies anything — it only ever reports, and it keeps its place in
# the graph, so requires= and after= still say where in the order it falls and
# a run can tell you what to do before the next thing rather than after it.
#
# detect= is optional. With one, the step answers for itself and goes quiet the
# moment it is done. Without one it stands until the declaration is removed,
# which is the honest answer when nothing on the machine records the fact.
manual_check() {
    local detect="${P[detect]:-}" secs="${P[timeout]:-30}" rc
    if [[ -n "$detect" ]]; then
        with_timeout "$secs" "$detect" >/dev/null 2>&1; rc=$?
        (( rc == 0 )) && return 0
        if (( rc == TIMED_OUT )); then
            REASON="gave up after ${secs}s asking whether this is done"
            return $TIMED_OUT
        fi
    fi
    REASON="${P[do]:-${POS[1]}}"
    return 1
}

manual_undo() { return 0 }

manual_revert() { return 0 }

manual_describe() { print -r -- "${POS[1]}" }
