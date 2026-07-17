#!/usr/bin/env zsh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ -t 0 ]] || { log "no terminal — skipping interactive setup"; exit 0; }

tool="$REPO_ROOT/vendor/macos_automation_scripts/redmi_pad_screenshot_to_clip_board"

pair_tablet() {
    echo
    read -r "ipport?  tablet pairing address (ip:port from 'Pair device with code'): "
    read -r "code?  pairing code: "
    adb pair "$ipport" "$code" || { warn "pairing failed"; return 1 }
    read -r "connport?  connect address (ip:port from the main Wireless debugging screen, empty to rely on mDNS): "
    [[ -n "$connport" ]] && adb connect "$connport"
    zsh "$tool/setup.sh"
    log "testing screenshot..."
    zsh "$tool/shot.sh" && log "screenshot OK — it is on your clipboard"
}

while true; do
    echo
    echo "Interactive setup — pick a step (enter to finish):"
    echo "  1) pair redmi tablet for screenshots (adb wireless pairing)"
    read -r "choice?> "
    case "${choice:-}" in
        1) pair_tablet || true ;;
        "") break ;;
        *) echo "unknown choice" ;;
    esac
done
