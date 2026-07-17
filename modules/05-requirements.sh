#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

xcode-select -p >/dev/null 2>&1 || { log "installing Command Line Tools"; xcode-select --install; }

if ! /usr/bin/pgrep -q oahd; then
    log "installing Rosetta 2 (needed by x86-only apps like AmneziaVPN)"
    if sudo -n true 2>/dev/null; then
        sudo softwareupdate --install-rosetta --agree-to-license
    elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
        sudo -A softwareupdate --install-rosetta --agree-to-license
    else
        warn "no sudo available — run: sudo softwareupdate --install-rosetta --agree-to-license"
    fi
fi

if ! security find-identity -p codesigning 2>/dev/null | grep -q mac-setup-codesign; then
    log "creating mac-setup-codesign certificate (stable identity keeps TCC grants across rebuilds)"
    tmp="$(mktemp -d)"
    cat > "$tmp/ext.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = mac-setup-codesign
[v3]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF
    openssl req -x509 -newkey rsa:2048 -keyout "$tmp/k.key" -out "$tmp/c.crt" -days 3650 -nodes -config "$tmp/ext.cnf" 2>/dev/null
    openssl pkcs12 -export -out "$tmp/b.p12" -inkey "$tmp/k.key" -in "$tmp/c.crt" -passout pass:tmppass
    security import "$tmp/b.p12" -k "$HOME/Library/Keychains/login.keychain-db" -f pkcs12 -P tmppass -T /usr/bin/codesign -T /usr/bin/security
    rm -rf "$tmp"
fi

if xcodebuild -version >/dev/null 2>&1; then
    log "full Xcode present: $(xcodebuild -version | head -1)"
else
    warn "full Xcode missing — needed to build the AeroSpace fork (module 30 falls back to the brew cask):"
    cat <<'EOF'
      1. Install Xcode from the App Store (needs your Apple ID)
      2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
      3. sudo xcodebuild -license accept
      4. Rerun: ./sync 30
EOF
fi
