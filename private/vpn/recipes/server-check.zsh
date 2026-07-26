# Is the far end running exactly our config? Compares a hash, so the secret
# itself never crosses the wire for a mere check.
host=$(./mac secret get server-host 2>/dev/null) || exit 1
SSH=(ssh -i "$HOME/.ssh/id_ed25519_server" -o BatchMode=yes -o ConnectTimeout=8 "root@$host")
want=$(zsh private/vpn/recipes/server-render.zsh | shasum -a 256 | cut -d' ' -f1)
have=$("${SSH[@]}" 'sha256sum /etc/olcrtc/server.yaml 2>/dev/null | cut -d" " -f1; systemctl is-active olcrtc.service') || exit 1
[[ "${have%%$'\n'*}" == "$want" && "${have##*$'\n'}" == active ]]
