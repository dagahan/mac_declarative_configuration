# Pushes the server's config (and the binary, if missing) over SSH. Only the
# Mac can decrypt, so it renders and the server merely receives.
# The run provider already puts us in the repo root; $ROOT is not set here.
set -e
SSH=(ssh -i "$HOME/.ssh/id_ed25519_server" -o BatchMode=yes -o ConnectTimeout=10 root@46.8.96.30)
host=$(./mac secret get server-host)
SSH=(ssh -i "$HOME/.ssh/id_ed25519_server" -o BatchMode=yes -o ConnectTimeout=10 "root@$host")

want=$(zsh private/vpn/recipes/server-render.zsh)
[[ -n "$want" ]] || { print -u2 "refusing to deploy an empty config"; exit 1 }

if ! "${SSH[@]}" 'test -x /usr/local/bin/olcrtc'; then
    scp -i "$HOME/.ssh/id_ed25519_server" -o BatchMode=yes -q \
        vendor/olcrtc/build/olcrtc-linux-amd64 "root@$host:/usr/local/bin/olcrtc"
    "${SSH[@]}" 'chmod 755 /usr/local/bin/olcrtc'
fi

print -r -- "$want" | "${SSH[@]}" 'cat > /etc/olcrtc/server.yaml && chmod 600 /etc/olcrtc/server.yaml'
"${SSH[@]}" 'systemctl restart olcrtc.service'
sleep 3
"${SSH[@]}" 'systemctl is-active olcrtc.service' | grep -q active
