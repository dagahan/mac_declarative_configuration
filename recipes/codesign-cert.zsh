set -euo pipefail
tmp="$(mktemp -d)"
cat > "$tmp/ext.cnf" <<'CNF'
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
CNF
openssl req -x509 -newkey rsa:2048 -keyout "$tmp/k.key" -out "$tmp/c.crt" \
    -days 3650 -nodes -config "$tmp/ext.cnf" 2>/dev/null
openssl pkcs12 -export -out "$tmp/b.p12" -inkey "$tmp/k.key" -in "$tmp/c.crt" -passout pass:tmppass
security import "$tmp/b.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -f pkcs12 -P tmppass -T /usr/bin/codesign -T /usr/bin/security
rm -rf "$tmp"
