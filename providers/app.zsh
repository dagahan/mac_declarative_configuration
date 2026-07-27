# Externally-downloaded apps. Say as little as one url= or github=; everything
# else is inferred on first install and written to apps.lock for review.
# NB: never name a local 'path' here — zsh ties it to PATH and wipes it.
_app_name()   { print -r -- "${P[name]:-${(C)POS[1]}}" }
_app_path()   {
    local p="${P[path]:-$(lock_get "${POS[1]}" path)}"
    print -r -- "${p:-/Applications/$(_app_name).app}"
}
_app_format() {
    local f="${P[format]:-}"
    [[ -n "$f" ]] && { print -r -- "$f"; return }
    local u="${P[url]:-$(lock_get "${POS[1]}" url)}"
    case "${u:l}" in
        *.dmg) print -r -- dmg ;;
        *.pkg) print -r -- pkg ;;
        *.zip) print -r -- zip ;;
        *.tar.gz|*.tgz) print -r -- tar ;;
        *) print -r -- dmg ;;
    esac
}
_app_version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null }
_app_bundle()  { defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null }
# codesign prints "not set" for ad-hoc/unsigned bundles; treat that as no pin.
_app_teamid()  {
    local t
    t=$(codesign -dv --verbose=4 "$1" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')
    [[ "$t" == "not set" ]] && t=''
    print -r -- "$t"
}
_app_proc()    { local p="${P[proc]:-}"; print -r -- "${p:-$(_app_name)}" }

app_check() {
    local name=${POS[1]} dest have want
    dest=$(_app_path)
    [[ -e "$dest" ]] || { REASON="not installed"; return 1 }
    want=$(lock_get "$name" bundle_version)
    [[ -z "$want" ]] && { REASON="installed but unrecorded — will adopt into apps.lock"; return 1 }
    have=$(_app_version "$dest")
    [[ "$have" == "$want" ]] && return 0
    REASON="$have → $want"
    return 1
}

_app_adopt() {
    local name=$1 dest=$2
    lock_set "$name" "path=$dest" "bundle=$(_app_bundle "$dest")" \
        "bundle_version=$(_app_version "$dest")" "teamid=$(_app_teamid "$dest")" \
        "adopted=$(date -u '+%Y-%m-%d')"
    return 0
}

_app_fetch() {
    local url=$1 want=$2 tmp sha
    mkdir -p "$STATE/cache"
    if [[ -n "$want" && -f "$STATE/cache/$want" ]]; then print -r -- "$STATE/cache/$want"; return 0; fi
    tmp="$STATE/cache/.dl.$$"
    curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; REASON="download failed: $url"; return 1 }
    sha=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
    if [[ -n "$want" && "$sha" != "$want" ]]; then
        rm -f "$tmp"; REASON="sha256 mismatch (got $sha, lock says $want)"; return 1
    fi
    mv -f "$tmp" "$STATE/cache/$sha"
    print -r -- "$STATE/cache/$sha"
}

# Stages the payload's .app into $2 without touching the installed copy.
_app_stage() {
    local file=$1 out=$2 fmt=$3 mnt found
    rm -rf "$out"; mkdir -p "$out"
    case $fmt in
        dmg)
            mnt=$(mktemp -d)
            hdiutil attach "$file" -mountpoint "$mnt" -nobrowse -quiet || { REASON="cannot mount dmg"; return 1 }
            found=$(find "$mnt" -maxdepth 2 -name '*.app' -print -quit 2>/dev/null)
            if [[ -z "$found" ]]; then
                found=$(find "$mnt" -maxdepth 2 -name '*.pkg' -print -quit 2>/dev/null)
                [[ -n "$found" ]] && { cp "$found" "$out/payload.pkg"; hdiutil detach "$mnt" -quiet; print -r -- pkg; return 0 }
                hdiutil detach "$mnt" -quiet; REASON="no .app or .pkg inside the dmg"; return 1
            fi
            ditto "$found" "$out/${found:t}"
            hdiutil detach "$mnt" -quiet
            ;;
        zip)  ditto -x -k "$file" "$out" || { REASON="unzip failed"; return 1 } ;;
        tar)  tar -xzf "$file" -C "$out" || { REASON="untar failed"; return 1 } ;;
        pkg)  cp "$file" "$out/payload.pkg"; print -r -- pkg; return 0 ;;
        *)    REASON="unsupported format '$fmt'"; return 1 ;;
    esac
    found=$(find "$out" -maxdepth 2 -name '*.app' -print -quit)
    [[ -n "$found" ]] || { REASON="no .app in payload"; return 1 }
    return 0
}

app_apply() {
    local name=${POS[1]} dest fmt url sha stage staged team want_team proc kind
    dest=$(_app_path)

    if [[ -e "$dest" && -z "$(lock_get "$name" bundle_version)" ]]; then
        _app_adopt "$name" "$dest"
        REASON=''
        return 0
    fi

    url=$(lock_get "$name" url)
    sha=$(lock_get "$name" sha256)
    [[ -n "$url" ]] || { REASON="no source recorded — run: mac up $name"; return 1 }

    local file; file=$(_app_fetch "$url" "$sha") || return 1
    fmt=$(_app_format)
    stage="$STATE/cache/stage-$name"
    kind=$(_app_stage "$file" "$stage" "$fmt") || return 1

    if [[ "$kind" == pkg ]]; then
        if ! sudo -n installer -pkg "$stage/payload.pkg" -target / >/dev/null 2>&1; then
            REASON="pkg install needs sudo — run 'sudo -v' then retry"
            return 1
        fi
    else
        staged=$(find "$stage" -maxdepth 2 -name '*.app' -print -quit)
        want_team=$(lock_get "$name" teamid)
        team=$(_app_teamid "$staged")
        if [[ -n "$want_team" && "$want_team" != "$team" ]]; then
            REASON="signed by '$team', lock pins '$want_team' — refusing"
            return 1
        fi
        proc=$(_app_proc)
        _svc_stop "$proc"
        rm -rf "$dest.new"
        ditto "$staged" "$dest.new" || { REASON="staging copy failed"; return 1 }
        rm -rf "$dest"
        mv "$dest.new" "$dest" || { REASON="install swap failed"; return 1 }
        xattr -dr com.apple.quarantine "$dest" 2>/dev/null
    fi

    rm -rf "$stage"
    before_exists "app:$name" || before_save "app:$name" "path:$dest"
    lock_set "$name" "path=$dest" "bundle=$(_app_bundle "$dest")" \
        "bundle_version=$(_app_version "$dest")" "installed=$(date -u '+%Y-%m-%d')"
    REASON=''
    return 0
}

app_revert() {
    local id=$1 name dest
    name=${id#app:}
    dest=$(lock_get "$name" path)
    [[ -n "$dest" ]] || dest=$(before_get "$id" | sed 's/^path://')
    if [[ "$(lock_get "$name" format)" == pkg ]]; then
        REASON="pkg receipts must be removed by hand: pkgutil --pkgs | grep -i $name"
        return 1
    fi
    [[ -n "$dest" && -e "$dest" ]] && rm -rf "$dest"
    lock_drop "$name"
    return 0
}

app_describe() { print -r -- "$(_app_name)" }
