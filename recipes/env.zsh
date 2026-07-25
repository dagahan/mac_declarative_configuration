export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

[[ -d /Applications/Xcode.app ]] || { print -ru2 -- "full Xcode is required (see the base unit)"; exit 1 }

# Real cargo/rustc live in the active rustup toolchain; homebrew's rustup
# creates no ~/.cargo/bin proxies.
if command -v rustup >/dev/null 2>&1; then
    _tc="$(rustup show active-toolchain 2>/dev/null | awk '{print $1}')"
    [[ -n "$_tc" ]] && export PATH="$HOME/.rustup/toolchains/$_tc/bin:$PATH"
fi
