# One list of software, and Homebrew as the only thing that installs any of it.
#
# software.toml is the whole authoring surface. Everything else here is
# rendering, and what it renders is a cache: the Brewfile and the cask files
# live under $STATE, not in the repo, because with [brew] and [cask] spelled
# out there is nothing in them the manifest does not already say. software.toml
# is the lock — a version bump is a diff in the file you edited.
typeset -g MANIFEST="$ROOT/software.toml"
typeset -g BREWFILE="$STATE/Brewfile"
typeset -g TAPDIR="$STATE/tap"
typeset -g TAPNAME="mac-setup/local"

typeset -ga SW_TAP SW_BREW SW_CASK SW_DOWNLOAD SW_MANUAL SW_UNRESOLVED
typeset -gA SW_ATTR
typeset -gi SW_LOADED=0

_sw_trim() {
    setopt localoptions extendedglob
    local s=$1
    s="${s##[[:space:]]##}"
    s="${s%%[[:space:]]##}"
    print -r -- "$s"
}

# A deliberately small subset: section headers, bare names, and key = "value".
# Anything TOML can express that this cannot is a feature the manifest does not
# have, which is the point.
software_load() {
    (( SW_LOADED )) && return 0
    SW_LOADED=1
    SW_TAP=(); SW_BREW=(); SW_CASK=(); SW_DOWNLOAD=(); SW_MANUAL=(); SW_ATTR=()
    [[ -f "$MANIFEST" ]] || return 0
    local line sect='' name='' key val
    while IFS= read -r line; do
        line=$(_sw_trim "${line%%$'\r'}")
        [[ -z "$line" || "$line" == '#'* ]] && continue
        if [[ "$line" == '['*']' ]]; then
            sect="${${line#\[}%\]}"
            name=''
            case "$sect" in
                download.*) name="${sect#download.}"; sect=download; SW_DOWNLOAD+=("$name") ;;
                manual.*)   name="${sect#manual.}";   sect=manual;   SW_MANUAL+=("$name") ;;
                tap|brew|cask) ;;
                *) die "software.toml: unknown section [$sect]" ;;
            esac
            continue
        fi
        if [[ "$line" == *=* && "$sect" == (download|manual) ]]; then
            key=$(_sw_trim "${line%%=*}")
            val=$(_sw_trim "${line#*=}")
            val="${val%\"}"; val="${val#\"}"
            SW_ATTR[$sect.$name.$key]="$val"
            continue
        fi
        line="${line%%[[:space:]]#*}"
        case "$sect" in
            tap)  SW_TAP+=("$line") ;;
            brew) SW_BREW+=("$line") ;;
            cask) SW_CASK+=("$line") ;;
            '')   die "software.toml: '$line' is outside any section" ;;
            *)    die "software.toml: [$sect] takes key = \"value\" lines, not '$line'" ;;
        esac
    done < "$MANIFEST"
}

sw_attr() { print -r -- "${SW_ATTR[$1.$2.$3]:-}" }

# ── learning what is inside a download ────────────────────────────────────
#
# A url is the only thing you can be expected to know. What the payload is
# called, which version it claims to be and what it hashes to are all facts
# about the file itself, so they are read off the file once and remembered,
# not transcribed by hand into the manifest.
#
# Anything stated explicitly still wins — this fills in blanks, it never
# overrules. The record is keyed by the url it was learned from, so changing
# the link re-reads everything rather than installing yesterday's answers.

_sw_learned_file() { print -r -- "$STATE/downloads/$1" }

_sw_learned() {
    local n=$1 key=$2 f line
    f=$(_sw_learned_file "$n")
    [[ -f "$f" ]] || return 1
    [[ "$(sed -n '1s/^url=//p' "$f")" == "$(sw_attr download "$n" url)" ]] || return 1
    line=$(sed -n "s/^$key=//p" "$f")
    [[ -n "$line" ]] || return 1
    print -r -- "$line"
}

# Declared, else learned, else nothing.
sw_field() {
    local n=$1 key=$2 v
    v=$(sw_attr download "$n" "$key")
    [[ -n "$v" ]] && { print -r -- "$v"; return 0 }
    _sw_learned "$n" "$key"
}

sw_resolved() {
    local n=$1
    [[ -n "$(sw_field "$n" app)" || -n "$(sw_field "$n" pkg)" ]]
}

_sw_version_from_name() {
    local base="${1:t}" v
    v=$(print -r -- "$base" | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)
    print -r -- "$v"
}

# How big the payload is, and whether the server will let a transfer resume.
# Sets SW_TOTAL and SW_RANGES; both are 0 when the server would not say.
#
# Two questions, one request where possible. A HEAD is the polite way to ask and
# plenty of file hosts either refuse it or answer it with a redirect to
# something that is not the file, so the fallback asks for a single byte: the
# Content-Range in the reply carries the full size *and* proves that resuming
# will work. Guessing that it will is how a download gets to 1.7 GiB and then
# discovers it has to start over.
_sw_probe() {
    local url=$1 hdrs
    typeset -gi SW_TOTAL=0 SW_RANGES=0
    hdrs=$(curl -fsSLI --connect-timeout 20 --max-time 60 "$url" 2>/dev/null)
    SW_TOTAL=$(print -r -- "$hdrs" | awk '
        { l = tolower($0); sub(/\r$/, "", l) }
        l ~ /^content-length:/ { n = $2 + 0 }
        END { print n + 0 }')
    [[ "${hdrs:l}" == *"accept-ranges: bytes"* ]] && SW_RANGES=1
    (( SW_TOTAL > 0 && SW_RANGES )) && return 0

    # --max-filesize: a host that does not do ranges answers this with the whole
    # file, and downloading the payload twice to find out how big it is would be
    # a strange way to save time. The headers still arrive; the body does not.
    hdrs=$(curl -fsSL --connect-timeout 20 --max-time 60 --max-filesize 65536 \
        -r 0-0 -o /dev/null -D - "$url" 2>/dev/null)
    local -i n
    n=$(print -r -- "$hdrs" | awk '
        { l = tolower($0); sub(/\r$/, "", l) }
        l ~ /^content-range:/ { split(l, a, "/"); n = a[2] + 0 }
        END { print n + 0 }')
    if (( n > 0 )); then
        # Content-Range is both answers at once: the total after the slash, and
        # the proof that asking for part of the file does something.
        SW_TOTAL=$n
        SW_RANGES=1
        return 0
    fi
    if (( SW_TOTAL == 0 )); then
        SW_TOTAL=$(print -r -- "$hdrs" | awk '
            { l = tolower($0); sub(/\r$/, "", l) }
            l ~ /^content-length:/ { n = $2 + 0 }
            END { print n + 0 }')
    fi
    return 0
}

_sw_size() { local -a s; zstat -A s +size "$1" 2>/dev/null || return 0; print -r -- "${s[1]:-0}" }

# A truncated download is the failure that looks like every other failure: the
# unpacker just says the file is malformed. Multi-gigabyte payloads stall often
# enough that it is worth knowing the difference, so the bytes are counted
# against what the server promised before anything tries to open them.
#
# Everything slow here says which of the two slow things it is doing. "Fetching"
# and "reading the dmg" take minutes and seconds respectively and fail for
# unrelated reasons, and a single label over both of them was how a download
# that never finished got reported as a mount that would not work.
_sw_fetch() {
    local n=$1 url=$2 part=$3 label
    local -i want have start t0 secs attempt rc

    spin_start "asking how big $n is"
    _sw_probe "$url"
    spin_stop
    want=$SW_TOTAL

    for attempt in 1 2; do
        cancelled && { REASON="cancelled before $n started"; return 1 }
        start=$(_sw_size "$part")
        if (( want > 0 && start == want )); then
            print -r -- "  $S_OK have $n already ${C_DIM}$(fmt_bytes $want)${C_RESET}"
            return 0
        fi
        # Resuming a server that will not do ranges appends the whole file onto
        # the bytes already there and produces a plausible-looking corrupt one,
        # so it is only attempted when the probe saw the offer.
        if (( start > 0 && ! SW_RANGES )); then
            print -r -- "  $S_WARN $n cannot be resumed here — starting over"
            : > "$part"; start=0
        fi
        if (( start > 0 )); then
            label="resuming $n"
            print -r -- "  $S_DOT resuming $n ${C_DIM}from $(fmt_bytes $start)${C_RESET}"
        else
            label="downloading $n"
        fi

        t0=$EPOCHSECONDS
        prog_start "$label" "$part" "$want"
        # -C - resumes the part file rather than starting the transfer over, and
        # the speed floor gives up on a connection that has gone quiet instead
        # of holding the whole sync open. -sS: no progress meter, but keep the
        # error text — curl's own meter may never reach the terminal, so the
        # progress line watches the part file grow instead.
        sh_run "curl -fsSL -C - --retry 5 --retry-all-errors --retry-delay 2 \
            --connect-timeout 20 --speed-limit 1024 --speed-time 60 \
            -o ${(q)part} ${(q)url}"
        rc=$?
        prog_stop
        have=$(_sw_size "$part")

        cancelled && {
            REASON="cancelled — $(fmt_bytes $have) of $n kept for the next run"
            return 1 }

        # A host that dropped the connection and then refused the range request
        # has stranded whatever was already fetched. Nothing is recoverable from
        # those bytes, but the download itself still is — once, from zero.
        local low="${LAST_OUTPUT:l}"
        if (( rc != 0 )) && [[ "$low" == *"cannot resume"* || "$low" == *"byte ranges"* \
                            || "$low" == *"416"* ]]; then
            if (( attempt == 1 )); then
                print -r -- "  $S_WARN $n refused to resume — starting over from zero"
                : > "$part"
                SW_RANGES=0
                continue
            fi
        fi
        (( rc != 0 )) && { REASON="cannot fetch $n — $(sh_tail $rc)"; return 1 }

        if (( want > 0 && have != want )); then
            if (( attempt == 1 )); then
                print -r -- "  $S_WARN $n came back the wrong size — starting over from zero"
                : > "$part"
                continue
            fi
            REASON="incomplete download for $n — got $(fmt_bytes $have) of $(fmt_bytes $want)"
            return 1
        fi
        (( have > 0 )) || { REASON="cannot fetch $n — empty response"; return 1 }

        secs=$(( EPOCHSECONDS - t0 ))
        if (( secs > 0 )); then
            print -r -- "  $S_OK downloaded $n — $(fmt_bytes $have) ${C_DIM}in $(fmt_dur $secs) · $(fmt_bytes $(( (have - start) / secs )))/s${C_RESET}"
        else
            print -r -- "  $S_OK downloaded $n — $(fmt_bytes $have)"
        fi
        return 0
    done
    REASON="${REASON:-cannot fetch $n}"
    return 1
}

# Mounts the payload, notes what it holds, and unmounts again. Nothing is
# installed here; the only thing produced is knowledge.
_sw_learn() {
    local n=$1 url file part mnt found kind ver sha out rc
    typeset -g SW_INSIDE=''
    url=$(sw_attr download "$n" url)
    [[ -n "$url" ]] || { REASON="[download.$n] has no url"; return 1 }
    mkdir -p "$STATE/downloads" "$STATE/cache"
    file="$STATE/cache/learn-$n"
    part="$file.part"
    # A payload kept by an earlier run that could not read it goes back to being
    # the part file, where the size check finds it already complete and skips
    # the download entirely.
    [[ -f "$file" && ! -f "$part" ]] && mv -f "$file" "$part"
    rm -f "$file"
    # The part file deliberately outlives a failure: the next run resumes it
    # rather than fetching the same gigabytes again.
    _sw_fetch "$n" "$url" "$part" || return 1
    mv -f "$part" "$file" || { REASON="cannot fetch $n — $part is not readable"; return 1 }

    spin_start "reading $n"
    case "${url:l}" in
        *.zip|*.tar.gz|*.tgz)
            out="$STATE/cache/learn-$n.d"
            rm -rf "$out"; mkdir -p "$out"
            sh_run "ditto -x -k ${(q)file} ${(q)out}" \
                || sh_run "tar -xzf ${(q)file} -C ${(q)out}" \
                || { REASON="cannot unpack $n"; rm -rf "$out" "$file"; return 1 }
            found=$(find "$out" -maxdepth 3 -name '*.app' -print -quit 2>/dev/null); kind=app
            [[ -n "$found" ]] || { found=$(find "$out" -maxdepth 3 -name '*.pkg' -print -quit 2>/dev/null); kind=pkg }
            ;;
        *.pkg)
            found="$file"; kind=pkg
            ;;
        *)
            # A UDIF image ends in its koly trailer. Checking for it separates
            # "this is not the disk image the link promised" from the mount
            # failures worth reading hdiutil's own words about.
            if [[ "$(tail -c 512 "$file" | head -c 4)" != koly ]]; then
                REASON="not a disk image: $n — the url did not serve a dmg"
                rm -f "$file"; return 1
            fi
            mnt=$(mktemp -d)
            # Not -quiet: on failure hdiutil's stderr is the only account of why,
            # and suppressing it leaves the journal with nothing to show.
            sh_run "hdiutil attach ${(q)file} -mountpoint ${(q)mnt} -nobrowse -readonly" || {
                REASON="cannot mount the dmg for $n — $(sh_tail)"; rm -rf "$mnt" "$file"; return 1 }
            # Depth 4, not 2: a big installer is regularly a folder of parts with
            # the bundle one or two levels down, and refusing to look was read as
            # the image containing nothing at all.
            found=$(find "$mnt" -maxdepth 4 -name '*.app' -print -quit 2>/dev/null); kind=app
            [[ -n "$found" ]] || { found=$(find "$mnt" -maxdepth 4 -name '*.pkg' -print -quit 2>/dev/null); kind=pkg }
            [[ -n "$found" && "$kind" == app ]] && \
                ver=$(defaults read "$found/Contents/Info" CFBundleShortVersionString 2>/dev/null)
            # What is actually in there, for when none of it is installable. The
            # listing is the whole difference between "this needs a look" and
            # knowing what to write in software.toml.
            [[ -n "$found" ]] || SW_INSIDE=$(ls -A "$mnt" 2>/dev/null | head -8 | tr '\n' ' ')
            sh_run "hdiutil detach ${(q)mnt} -quiet"
            rmdir "$mnt" 2>/dev/null
            ;;
    esac
    if [[ -z "$found" ]]; then
        REASON="nothing installable inside $n — no .app and no .pkg"
        [[ -n "$SW_INSIDE" ]] && REASON+=" · it holds: ${SW_INSIDE% }"
        # The payload stays. It is the expensive thing in this whole operation
        # and there is nothing wrong with it — what is missing is a line in
        # software.toml saying what to install out of it, and re-fetching
        # gigabytes to try that again would be an absurd price for a one-word
        # edit.
        journal "learn $n found nothing installable; kept $file"
        rm -rf "$STATE/cache/learn-$n.d"
        return 1
    fi
    [[ "$kind" == app && -z "$ver" && -d "$found" ]] && \
        ver=$(defaults read "$found/Contents/Info" CFBundleShortVersionString 2>/dev/null)
    [[ -n "$ver" ]] || ver=$(_sw_version_from_name "$url")
    # Its own stage: hashing gigabytes is slow enough that under the "reading"
    # label it looks like the mount has hung.
    spin_start "checksumming $n"
    sha=$(shasum -a 256 "$file" | cut -d' ' -f1)
    spin_start "handing $n to homebrew"

    {
        print -r -- "url=$url"
        print -r -- "$kind=${found:t}"
        [[ -n "$ver" ]] && print -r -- "version=$ver"
        print -r -- "sha256=$sha"
    } > "$(_sw_learned_file "$n")"

    # Handing Homebrew the copy already on disk saves fetching the same bytes a
    # second time. Best effort: if the cache path cannot be worked out, brew
    # simply downloads it again.
    _sw_seed_brew_cache "$n" "$file"
    rm -rf "$file" "$STATE/cache/learn-$n.d"
    return 0
}

_sw_seed_brew_cache() {
    local n=$1 file=$2 dest
    _sw_render_one "$n" || return 0
    dest=$(brew --cache --cask "$TAPNAME/$n" 2>/dev/null) || return 0
    [[ -n "$dest" ]] || return 0
    mkdir -p "${dest:h}"
    cp -f "$file" "$dest" 2>/dev/null
    return 0
}

# ── rendering ─────────────────────────────────────────────────────────────

_sw_cask_file() { print -r -- "$TAPDIR/Casks/$1.rb" }

_sw_render_cask() {
    local n=$1 url ver sha app pkg desc home
    url=$(sw_attr download "$n" url)
    ver=$(sw_field "$n" version)
    sha=$(sw_field "$n" sha256)
    app=$(sw_field "$n" app)
    pkg=$(sw_field "$n" pkg)
    desc=$(sw_attr download "$n" desc)
    home=$(sw_attr download "$n" homepage)
    [[ -n "$url" ]] || { REASON="[download.$n] has no url"; return 1 }
    [[ -n "$app" || -n "$pkg" ]] || { REASON="[download.$n] has not been looked at yet"; return 1 }
    {
        print -r -- "# generated by mac sync from software.toml — edit the manifest, not this"
        print -r -- "cask \"$n\" do"
        # Homebrew pairs these: an unnamed version may only go with an unchecked
        # digest, because there is then nothing to say the file is still the file.
        if [[ -z "$ver" ]]; then
            print -r -- "  version :latest"
            print -r -- "  sha256 :no_check"
        else
            print -r -- "  version \"$ver\""
            if [[ -z "$sha" || "$sha" == no_check ]]; then
                print -r -- "  sha256 :no_check"
            else
                print -r -- "  sha256 \"$sha\""
            fi
        fi
        print -r -- ""
        print -r -- "  url \"$url\""
        print -r -- "  name \"${$(sw_attr download "$n" name):-$n}\""
        [[ -n "$desc" ]] && print -r -- "  desc \"$desc\""
        print -r -- "  homepage \"${home:-https://example.invalid/}\""
        print -r -- ""
        [[ -n "$app" ]] && print -r -- "  app \"$app\""
        [[ -n "$pkg" ]] && print -r -- "  pkg \"$pkg\""
        print -r -- "end"
    }
}

_sw_render_one() {
    local n=$1 out tmp
    out=$(_sw_cask_file "$n")
    mkdir -p "${out:h}"
    tmp=$(mktemp)
    if ! _sw_render_cask "$n" > "$tmp"; then rm -f "$tmp"; return 1; fi
    mv -f "$tmp" "$out"
    return 0
}

_sw_render_brewfile() {
    local n
    print -r -- "# generated by mac sync from software.toml — edit the manifest, not this"
    for n in "${SW_TAP[@]}";  do print -r -- "tap \"$n\""; done
    for n in "${SW_BREW[@]}"; do print -r -- "brew \"$n\""; done
    for n in "${SW_CASK[@]}"; do print -r -- "cask \"$n\""; done
    # adopt: an app already sitting in /Applications that is identical to the
    # pin is taken over rather than refused. Without it, anything installed
    # before Homebrew owned it is a permanent error.
    #
    # Anything not yet looked at is left out: naming a cask that does not exist
    # would make brew bundle fail on everything, not just on that one entry.
    for n in "${SW_DOWNLOAD[@]}"; do
        sw_resolved "$n" || continue
        print -r -- "cask \"$TAPNAME/$n\", args: { adopt: true }"
    done
}

# The generated tree is what Homebrew reads, so it has to exist before any
# bundle command runs.
software_link_tap() {
    local taps dest
    taps="$(brew --repository 2>/dev/null)/Library/Taps" || return 1
    [[ -d "$taps" ]] || { REASON="cannot find Homebrew's tap directory"; return 1 }
    dest="$taps/${TAPNAME%%/*}/homebrew-${TAPNAME#*/}"
    mkdir -p "${dest:h}" "$TAPDIR/Casks"
    if [[ "$(readlink "$dest" 2>/dev/null)" != "$TAPDIR" ]]; then
        rm -rf "$dest"
        ln -sfn "$TAPDIR" "$dest" || { REASON="cannot link $dest"; return 1 }
    fi
    # Homebrew refuses to load casks from a tap it was never told to trust. This
    # one is generated from software.toml, so trusting it is trusting the
    # manifest — idempotent, and it writes only to Homebrew's own trust.json.
    brew trust --tap "$TAPNAME" >/dev/null 2>&1
    return 0
}

# Writing a cache is not a change to the machine, so this runs during check too:
# the only drift worth reporting is a package that is missing, never a derived
# file that is merely out of date.
software_render() {
    local tmp out n
    software_load
    mkdir -p "$TAPDIR/Casks"
    SW_UNRESOLVED=()
    for n in "${SW_DOWNLOAD[@]}"; do
        if sw_resolved "$n"; then
            _sw_render_one "$n" || return 1
        else
            SW_UNRESOLVED+=("$n")
            rm -f "$(_sw_cask_file "$n")"
        fi
    done
    tmp=$(mktemp)
    if ! _sw_render_brewfile > "$tmp"; then rm -f "$tmp"; return 1; fi
    mv -f "$tmp" "$BREWFILE"
    # A cask whose declaration was deleted must not keep installing itself.
    for out in "$TAPDIR"/Casks/*.rb(N); do
        n="${out:t:r}"
        (( ${SW_DOWNLOAD[(Ie)$n]} )) || rm -f "$out"
    done
    return 0
}

# Reads whatever has not been read yet. Separate from rendering because it goes
# to the network: a check may never do this, and an apply must.
software_learn_missing() {
    local n rc=0
    software_render || return 1
    # No spinner here: _sw_learn names each of its own stages, and one label
    # spanning a download, a mount and a checksum told you only that something
    # was happening somewhere.
    for n in "${SW_UNRESOLVED[@]}"; do
        cancelled && return 1
        if _sw_learn "$n"; then
            spin_stop
            print -r -- "  $S_OK read $n — $(sw_field "$n" app)$(sw_field "$n" pkg) ${C_DIM}$(sw_field "$n" version)${C_RESET}"
        else
            spin_stop
            print -r -- "  $S_BAD $n — ${REASON}"
            rc=1
        fi
        cancelled && return 1
    done
    # Re-rendered so the Brewfile picks up whatever was just learned and leaves
    # out whatever was not: one unreadable entry must not stop everything else
    # from installing.
    software_render || return 1
    return $rc
}
