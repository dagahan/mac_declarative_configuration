#!/usr/bin/env zsh
# pair the redmi tablet over wi-fi, for screenshots
set -euo pipefail

REPO_ROOT="${0:A:h:h}"
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }

[[ -t 0 ]] || { log "needs a terminal"; exit 0; }

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
