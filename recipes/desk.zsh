set -euo pipefail
agent=com.mac-setup.desk
rescue=com.mac-setup.desk-rescue
plists="$HOME/.config/mac_setup/launchd"
desk=/Applications/Desk.app/Contents/MacOS/Desk
domain="gui/$(id -u)"

loaded() { launchctl print "$domain/$1" >/dev/null 2>&1 }
agent_running() { [[ "$(launchctl print "$domain/$agent" 2>/dev/null)" == *"state = running"* ]] }

case "${1:-build}" in
    build)
        source "${0:A:h}/env.zsh"
        cd "$BUILD_DIR"
        swift build -c release --product Desk
        bundle=.build/Desk.app
        rm -rf "$bundle"
        mkdir -p "$bundle/Contents/MacOS"
        cp "$(swift build -c release --show-bin-path)/Desk" "$bundle/Contents/MacOS/Desk"
        cp Info.plist "$bundle/Contents/Info.plist"
        ;;
    up)
        for job in $agent $rescue; do
            loaded $job && launchctl bootout "$domain/$job"
            launchctl bootstrap "$domain" "$plists/$job.plist"
        done
        for _ in {1..30}; do agent_running && break; sleep 0.1; done
        agent_running
        ;;
    down)
        [[ -x $desk ]] && $desk on || true
        for job in $rescue $agent; do
            loaded $job && launchctl bootout "$domain/$job" || true
        done
        ;;
    check)
        agent_running && loaded $rescue
        ;;
esac
