#!/bin/bash
# One-time server install. Idempotent — safe to re-run after a VPS rebuild.
#   ssh root@<host> 'bash -s' < private/vpn/server/setup.sh
set -euo pipefail

install -d -m 755 /usr/local/share/olcrtc/data
install -d -m 700 /etc/olcrtc

cat > /etc/systemd/system/olcrtc.service <<'UNIT'
[Unit]
Description=olcrtc tunnel endpoint
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/olcrtc /etc/olcrtc/server.yaml
Restart=always
RestartSec=5
DynamicUser=no
User=root
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/etc/olcrtc /usr/local/share/olcrtc
StandardOutput=append:/var/log/olcrtc.log
StandardError=append:/var/log/olcrtc.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable olcrtc.service >/dev/null

# Key-only SSH. The password that was mailed out stops mattering.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sshd -t && systemctl reload ssh

# Only SSH in; anything out.
if ! command -v nft >/dev/null; then apt-get update -qq && apt-get install -y -qq nftables >/dev/null; fi
cat > /etc/nftables.conf <<'NFT'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    tcp dport 22 accept
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output  priority 0; policy accept; }
}
NFT
systemctl enable nftables >/dev/null 2>&1 || true
nft -f /etc/nftables.conf

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades >/dev/null 2>&1 || true

echo "server ready: $(systemctl is-enabled olcrtc.service), ssh password auth $(sshd -T 2>/dev/null | grep -c '^passwordauthentication no') disabled"
