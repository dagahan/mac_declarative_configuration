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

# Mounts the payload, notes what it holds, and unmounts again. Nothing is
# installed here; the only thing produced is knowledge.
_sw_learn() {
    local n=$1 url file mnt found kind ver sha out rc
    url=$(sw_attr download "$n" url)
    [[ -n "$url" ]] || { REASON="[download.$n] has no url"; return 1 }
    mkdir -p "$STATE/downloads" "$STATE/cache"
    file="$STATE/cache/learn-$n"
    rm -f "$file"
    # -sS: no progress meter, but keep the error text. The meter is one enormous
    # line of carriage returns, and it is the only thing the failure reason
    # would otherwise have to quote.
    sh_run "curl -fsSL --retry 2 --connect-timeout 20 -o ${(q)file} ${(q)url}" || {
        REASON="cannot fetch $n — $(sh_tail)"; rm -f "$file"; return 1 }

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
            mnt=$(mktemp -d)
            sh_run "hdiutil attach ${(q)file} -mountpoint ${(q)mnt} -nobrowse -readonly -quiet" || {
                REASON="cannot mount the dmg for $n"; rm -rf "$mnt" "$file"; return 1 }
            found=$(find "$mnt" -maxdepth 2 -name '*.app' -print -quit 2>/dev/null); kind=app
            [[ -n "$found" ]] || { found=$(find "$mnt" -maxdepth 2 -name '*.pkg' -print -quit 2>/dev/null); kind=pkg }
            [[ -n "$found" && "$kind" == app ]] && \
                ver=$(defaults read "$found/Contents/Info" CFBundleShortVersionString 2>/dev/null)
            sh_run "hdiutil detach ${(q)mnt} -quiet"
            rmdir "$mnt" 2>/dev/null
            ;;
    esac
    if [[ -z "$found" ]]; then
        REASON="nothing installable inside $n — no .app and no .pkg"
        rm -rf "$file" "$STATE/cache/learn-$n.d"
        return 1
    fi
    [[ "$kind" == app && -z "$ver" && -d "$found" ]] && \
        ver=$(defaults read "$found/Contents/Info" CFBundleShortVersionString 2>/dev/null)
    [[ -n "$ver" ]] || ver=$(_sw_version_from_name "$url")
    sha=$(shasum -a 256 "$file" | cut -d' ' -f1)

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
    for n in "${SW_UNRESOLVED[@]}"; do
        cancelled && return 1
        spin_start "looking inside $n"
        if _sw_learn "$n"; then
            spin_stop
            print -r -- "  $S_OK read $n — $(sw_field "$n" app)$(sw_field "$n" pkg) ${C_DIM}$(sw_field "$n" version)${C_RESET}"
        else
            spin_stop
            print -r -- "  $S_BAD $n — ${REASON}"
            rc=1
        fi
    done
    # Re-rendered so the Brewfile picks up whatever was just learned and leaves
    # out whatever was not: one unreadable entry must not stop everything else
    # from installing.
    software_render || return 1
    return $rc
}
