# Everything in software.toml, in one resource. Homebrew does the work: it
# fetches, verifies the checksum, mounts the dmg, runs the pkg, strips the
# quarantine flag and knows how to upgrade and remove again — all of which a
# hand-rolled installer had to reimplement badly.
software_check() {
    local rc
    software_render || return 1
    software_link_tap || return 2
    # Reading a download means fetching it, so a check never does — it only says
    # that it has not happened yet.
    if (( ${#SW_UNRESOLVED} )); then
        REASON="${(j:, :)SW_UNRESOLVED} not looked at yet — sync will fetch and read ${${#SW_UNRESOLVED}/#1/it}"
        return 1
    fi
    local secs="${P[timeout]:-300}"
    with_timeout "$secs" "brew bundle check --no-upgrade --file=${(q)BREWFILE}" >/dev/null 2>&1; rc=$?
    (( rc == 0 )) && return 0
    (( rc == TIMED_OUT )) && { REASON="gave up after ${secs}s asking Homebrew"; return $TIMED_OUT }
    REASON=$(_software_missing)
    return 1
}

_software_missing() {
    local -a lines
    # Two reasons this used to report nothing but the fallback below. Homebrew
    # says what is missing on stderr, which was being discarded, and it writes
    # "→ Cask android-studio needs to be installed.", which an anchored match
    # could not have found either. Kept unanchored and cut to the two words that
    # are the answer, so the next change to the sentence does not break it again.
    lines=(${(f)"$(brew bundle check --no-upgrade --file="$BREWFILE" --verbose 2>&1 | grep -oE '(Cask|Formula|Tap) [^ ]+' )"})
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
    local rc unread=0
    software_link_tap || return 1
    software_learn_missing || unread=1
    # A ^C during a download means stop, not "skip the download and go install
    # everything else" — starting the longest step of the run is the opposite of
    # what was asked for.
    cancelled && { REASON="cancelled while reading downloads"; return 1 }
    # Its own line: learning replaced the caller's spinner with one per download,
    # and the install that follows can be the longest part of the whole run.
    # Homebrew's own meter never reaches the terminal, so the line watches its
    # part files grow the same way a [download] does — otherwise a multi-gigabyte
    # cask is indistinguishable from a hang for as long as it takes.
    prog_start_glob "installing packages" \
        "${HOMEBREW_CACHE:-$HOME/Library/Caches/Homebrew}/downloads/*.incomplete"
    sh_run "brew bundle --file=${(q)BREWFILE} --no-upgrade"; rc=$?
    prog_stop
    if (( rc != 0 )); then REASON=$(sh_tail $rc); return 1; fi
    # Everything installable was installed; the run still failed, but it says so
    # about the entry that could not be read rather than about all of them.
    if (( unread )); then
        REASON="could not read: ${(j:, :)SW_UNRESOLVED}"
        return 1
    fi
    REASON=''
    return 0
}

software_describe() { print -r -- "software.toml" }
