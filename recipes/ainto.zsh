source "${0:A:h}/env.zsh"
set -euo pipefail
command -v cargo >/dev/null || { print -ru2 -- "cargo not found — the base unit installs the Rust toolchain"; exit 1 }
cd "$BUILD_DIR"
cargo build --release --manifest-path ainto-core/Cargo.toml
cd AintoApp
xcodegen generate
xcodebuild -scheme AintoApp -configuration Release -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO build
