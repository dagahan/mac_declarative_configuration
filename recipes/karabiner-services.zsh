#!/usr/bin/env zsh
# Karabiner's launchd jobs, which the cask registers system-wide and enabled.
# Left alone they start at every boot and remap the keyboard against apps that
# are not running — cmd+space becomes Ainto's hotkey, Ainto is down, and there is
# no launcher and no Spotlight. `launchctl disable` persists across reboots, so
# `down` is what guarantees a stock keyboard on a machine nobody has brought up.
#
# Karabiner-VirtualHIDDevice-Daemon is deliberately left enabled: it is an inert
# driver shim without the core service, and booting it out can re-trigger the
# system-extension approval prompt, which only Nick can click.
set -uo pipefail

GUI_LABELS=(
    org.pqrs.service.agent.karabiner_console_user_server
    org.pqrs.service.agent.Karabiner-Core-Service-rev2
    org.pqrs.service.agent.Karabiner-NotificationWindow
    org.pqrs.service.agent.Karabiner-Menu
)
SYSTEM_LABELS=(
    org.pqrs.service.daemon.Karabiner-Core-Service
)
MANAGER="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
AGENT_PLISTS="/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents v2.app/Contents/Library/LaunchAgents"
GUI="gui/$(id -u)"

_state() { launchctl print-disabled "$1" 2>/dev/null | grep -F "\"$2\"" | grep -q disabled && print -r -- disabled || print -r -- enabled }

status() {
    local l
    for l in "${GUI_LABELS[@]}";    do printf '  %-58s %-8s %s\n' "$l" "$(_state "$GUI" "$l")" "$(launchctl print "$GUI/$l" 2>/dev/null | awk '/state = /{print $3; exit}')"; done
    for l in "${SYSTEM_LABELS[@]}"; do printf '  %-58s %-8s %s\n' "$l" "$(_state system "$l")" "$(launchctl print "system/$l" 2>/dev/null | awk '/state = /{print $3; exit}')"; done
}

up() {
    local l
    for l in "${SYSTEM_LABELS[@]}"; do
        sudo launchctl enable "system/$l" 2>/dev/null
        sudo launchctl kickstart "system/$l" 2>/dev/null
    done
    "$MANAGER" activate >/dev/null 2>&1
    # `enable` only clears the disabled flag; `down` booted these out of the domain
    # entirely, so there is nothing left to kickstart. Relaunching the app does not
    # help either — it registers its agents once and is a no-op while already
    # running. Bootstrapping the shipped plists back into the domain is what
    # actually returns them.
    local p
    for l in "${GUI_LABELS[@]}"; do
        launchctl enable "$GUI/$l" 2>/dev/null
    done
    for p in "$AGENT_PLISTS"/*.plist(N); do
        launchctl bootstrap "$GUI" "$p" 2>/dev/null
    done
    for l in "${GUI_LABELS[@]}"; do
        launchctl kickstart "$GUI/$l" 2>/dev/null
    done
    # The grabber needs a moment before it reports itself as having taken the
    # keyboard; reporting success earlier would let `up` claim a working remap
    # that is not live yet.
    local i
    for i in {1..25}; do
        pgrep -qf karabiner_console_user_server && return 0
        sleep 0.2
    done
    print -ru2 -- "karabiner did not come up"
    return 1
}

down() {
    local l rc=0
    for l in "${GUI_LABELS[@]}"; do
        launchctl bootout "$GUI/$l" 2>/dev/null
        launchctl disable "$GUI/$l" 2>/dev/null
    done
    # The user agents are what feed the grabber its config, so taking them down
    # already stops the remapping. The system daemon still needs to go, or it
    # comes back at the next boot — but not being able to is worth reporting
    # rather than aborting: a keyboard that is half handed back beats one that is
    # still fully remapped.
    if sudo -n true 2>/dev/null; then
        for l in "${SYSTEM_LABELS[@]}"; do
            sudo -n launchctl bootout "system/$l" 2>/dev/null
            sudo -n launchctl disable "system/$l" 2>/dev/null
        done
    else
        print -ru2 -- "no root: $SYSTEM_LABELS still enabled and will start at boot"
        rc=1
    fi
    local i
    for i in {1..25}; do
        pgrep -qf karabiner_console_user_server || return $rc
        sleep 0.2
    done
    print -ru2 -- "karabiner user agent is still running"
    return 1
}

# True when every job is disabled AND none is running — the state a boot inherits.
is_down() {
    local l
    for l in "${GUI_LABELS[@]}";    do [[ "$(_state "$GUI" "$l")" == disabled ]] || return 1; done
    for l in "${SYSTEM_LABELS[@]}"; do [[ "$(_state system "$l")" == disabled ]] || return 1; done
    pgrep -qf karabiner_console_user_server && return 1
    return 0
}

case "${1:-status}" in
    up)      up ;;
    down)    down ;;
    is-down) is_down ;;
    status)  status ;;
    *)       print -ru2 -- "usage: karabiner-services.zsh <up|down|is-down|status>"; exit 2 ;;
esac
