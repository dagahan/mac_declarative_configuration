# The only health check that means anything: fetch through the tunnel and see
# the server's own address come back. A listening port proves nothing.
want=$(./mac secret get server-host 2>/dev/null)
[[ -n "$want" ]] || exit 1
got=$(curl -s -m 20 --socks5-hostname 127.0.0.1:8808 https://icanhazip.com 2>/dev/null)
[[ "$got" == "$want" ]]
