# The tunnel. Never runs on a bare `mac sync` — only `mac sync proxy`.
opt_in=1
requires=(brew)

build olcrtc from=vendor/olcrtc recipe=private/vpn/recipes/olcrtc-build.zsh \
      artifact=build/olcrtc app="$HOME/.local/bin/olcrtc" proc=olcrtc sign=0

file olcrtc-client from=private/vpn/config/olcrtc/client.yaml.tmpl \
     at="$HOME/.config/olcrtc/client.yaml" sensitive=1

file singbox-config from=private/vpn/config/singbox/proxy.json.tmpl \
     at="$HOME/.config/sing-box/config.json"

file undo-script from=private/vpn/config/undo-proxy.command \
     at="$HOME/Desktop/UNDO-PROXY.command"

file olcrtc-plist from=private/vpn/config/launchd/olcrtc.plist.tmpl \
     at="$HOME/Library/LaunchAgents/com.mac-setup.olcrtc.plist"

daemon olcrtc label=com.mac-setup.olcrtc after='file:olcrtc-plist'

run server-config why="the far end must hold the same key and room; ssh is the only way to tell it" \
    check='zsh private/vpn/recipes/server-check.zsh' \
    apply='zsh private/vpn/recipes/server-deploy.zsh' \
    timeout=60 after='daemon:olcrtc'

run tunnel-alive why="a listening port proves nothing — only an end-to-end fetch does" \
    check='zsh private/vpn/recipes/proxy-probe.zsh' \
    apply='true' timeout=40 after='run:server-config'
