# Everything in software.toml, in one resource. Homebrew does the work: it
# fetches, verifies the checksum, mounts the dmg, runs the pkg, strips the
# quarantine flag and knows how to upgrade and remove again — all of which a
# hand-rolled installer had to reimplement badly.
software_check() {
    local rc
    software_render || return 1
    software_link_tap || return 2
    local secs="${P[timeout]:-300}"
    with_timeout "$secs" "brew bundle check --no-upgrade --file=${(q)BREWFILE}" >/dev/null 2>&1; rc=$?
    (( rc == 0 )) && return 0
    (( rc == TIMED_OUT )) && { REASON="gave up after ${secs}s asking Homebrew"; return $TIMED_OUT }
    REASON=$(_software_missing)
    return 1
}

_software_missing() {
    local -a lines
    lines=(${(f)"$(brew bundle check --no-upgrade --file="$BREWFILE" --verbose 2>/dev/null | grep -E '^(Homebrew|Cask|Formula|Tap)' )"})
    (( ${#lines} )) || { print -r -- "some packages are missing"; return }
    if (( ${#lines} > 3 )); then
        print -r -- "${#lines} packages missing"
    else
        print -r -- "${(j:, :)lines}"
    fi
}

# Uninstalling everything Homebrew just installed is a worse outcome than
# leaving it installed — a cancelled sync should not strip the machine. The
# generated files are a cache rebuilt from software.toml on the next run, so
# there is nothing else here to put back.
software_undo() {
    undo_push "leave installed packages alone" ":"
    return 0
}

software_apply() {
    local rc
    software_render || return 1
    software_link_tap || return 1
    sh_run "brew bundle --file=${(q)BREWFILE} --no-upgrade"; rc=$?
    (( rc == 0 )) && { REASON=''; return 0 }
    REASON=$(sh_tail $rc)
    return 1
}

software_describe() { print -r -- "software.toml" }
