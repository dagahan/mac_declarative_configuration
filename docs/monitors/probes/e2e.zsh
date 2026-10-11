#!/usr/bin/env zsh
set -u
zmodload zsh/datetime
export PATH="/opt/homebrew/bin:$PATH"

typeset -g HERE=${0:A:h}
typeset -g OUT="$HOME/.local/state/mac_setup/monitors/e2e-$(strftime %Y%m%d-%H%M%S $EPOCHSECONDS)"
typeset -g EV="$OUT/events.jsonl" RESULTS="$OUT/results.txt"
typeset -g MAC=${HERE:h:h:h}/mac DESK_EVENTS="$HOME/.local/state/mac_setup/desk/events.log"
typeset -g LEFT=3996 RIGHT=39260
typeset -ga HELPERS STEPS
typeset -gi PASSED=0 FAILED=0
STEPS=(${@:-docked right-cable both-cables chord lock crash overview})
mkdir -p "$OUT"

probe() { swift "$HERE/probe.swift" "$@" 2>>"$OUT/stderr.log" }
mark() { print -r -- "{\"ts\":$EPOCHREALTIME,\"ev\":\"step\",\"name\":\"$1\"}" >> "$EV" }
say() { print -r -- ""; print -r -- "  $*" }
wait_enter() { local reply; print -rn -- "  press Enter when done "; read -r reply }

yes_no() {
    local reply
    print -rn -- "  $* [y/n] "
    read -r reply
    [[ ${reply:l} == y* ]]
}

verdict() {
    local name=$1 ok=$2 detail=${3:-}
    if (( ok )); then (( PASSED++ )); print -r -- "  PASS  $name${detail:+ — $detail}" | tee -a "$RESULTS"
    else (( FAILED++ )); print -r -- "  FAIL  $name${detail:+ — $detail}" | tee -a "$RESULTS"; fi
}

check() { local name=$1; shift; "$@"; verdict "$name" $(( $? == 0 )) }

desk() { $MAC desk "$@" }
panel_now() { desk status | sed -n 's/^panel_now=//p' }
monitor_keys() { aerospace list-monitors --format '%{monitor-key}' | sort -n | tr '\n' ' ' }
focused_monitor() { aerospace list-monitors --focused --format '%{monitor-key}' }
focused_workspace() { aerospace list-workspaces --focused }
workspace_of() { aerospace list-windows --all --format '%{window-id} %{workspace}' | awk -v id=$1 '$1 == id { print $2 }' }
windows_on() { aerospace list-windows --all --format '%{window-id} %{workspace}' | awk -v owner="$1-" 'index($2, owner) == 1' }
numbered_windows() { aerospace list-windows --all --format '%{window-id} %{workspace}' | awk '$2 ~ /^[0-9]$/' | sort }
main_workspace() { aerospace list-workspaces --monitor $(aerospace list-monitors --format '%{monitor-id} %{monitor-is-main}' | awk '$2 == "true" { print $1 }') --visible }

wait_until() {
    local seconds=$1 i
    shift
    for i in {1..$(( seconds * 10 ))}; do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

panel_is() { [[ $(panel_now) == $1 ]] }
monitors_are() { [[ $(monitor_keys) == "$1" ]] }

windows_float_on_main() {
    local snapshot=$1 host id workspace
    host=$(main_workspace)
    while read -r id workspace; do
        [[ $(workspace_of $id) == $host ]] || return 1
    done < "$snapshot"
}

windows_back_home() {
    local snapshot=$1 id workspace
    while read -r id workspace; do
        [[ $(workspace_of $id) == $workspace ]] || return 1
    done < "$snapshot"
}

seconds_from_last_monitor_to_panel() {
    python3 - "$EV" "$1" <<'EOF'
import json, sys
events = [json.loads(line) for line in open(sys.argv[1])]
since = float(sys.argv[2])
def real(d):
    return d.get("online") and not d.get("builtin") and not d.get("mirrors") and d.get("serial", 0) != 0 \
        and d.get("vendor") != 0x756E6B6E and d.get("model") != 0x76697274
states = [e for e in events if e["ev"] == "state" and e["ts"] >= since]
lost = next((e["ts"] for e in states if not any(real(d) for d in e["displays"])), None)
lit = next((e["ts"] for e in states if lost and e["ts"] >= lost and any(d.get("builtin") and d.get("online") for d in e["displays"])), None)
print("never" if lost is None or lit is None else f"{lit - lost:.2f}")
EOF
}

cleanup() {
    trap - EXIT INT TERM
    touch "$OUT/stop"
    sleep 1
    pkill -f "$HERE/probe.swift.*logger" 2>/dev/null
    kill ${HELPERS[@]} 2>/dev/null
    say "$PASSED passed, $FAILED failed — $RESULTS"
    say "If the laptop screen is dark with no monitor attached: mac desk on"
}

preflight() {
    say "The multi-monitor desk, end to end — about 5 minutes. Stay at the desk with the lid open."
    say "If the laptop screen ever stays dark with no monitor attached: wait 5 s, press ctrl+option+cmd+L,"
    say "or plug a monitor back in. Keep this terminal on monitor E (the left one)."
    local ok=1
    pgrep -qx AeroSpace || { say "AeroSpace is not running — run: mac workspace up"; ok=0 }
    [[ $(desk status | sed -n 's/^agent=//p') == running ]] || { say "the desk agent is not running — run: mac workspace up"; ok=0 }
    pgrep -qx karabiner_grabber || say "Karabiner's daemon is not running, so F3 cannot work — run mac workspace up and give it your password"
    monitors_are "$LEFT $RIGHT " || { say "expected monitors $LEFT and $RIGHT, AeroSpace sees: $(monitor_keys)"; ok=0 }
    (( ok )) || exit 1
    aerospace list-windows --all --format '%{window-id}|%{app-name}|%{workspace}' > "$OUT/layout-before.txt"
    probe logger "$EV" &
    HELPERS+=($!)
    wait_until 20 grep -qs logger-start "$EV" || { say "the display logger did not start"; exit 1 }
}

docked() {
    mark docked
    say "1. Docked"
    check "the laptop panel is off while docked" panel_is off
    check "E is $LEFT and R is $RIGHT" [ "$(aerospace list-monitors --format '%{monitor-letter}%{monitor-key}' | sort | tr '\n' ' ')" = "E$LEFT R$RIGHT " ]
    local main
    main=$(aerospace list-monitors --format '%{monitor-key} %{monitor-is-main}' | awk '$2 == "true" { print $1 }')
    say "Press option+R."; wait_enter
    check "option+R focuses the right monitor" [ "$(focused_monitor)" = $RIGHT ]
    say "Press option+E."; wait_enter
    check "option+E focuses the left monitor" [ "$(focused_monitor)" = $LEFT ]
    say "Press option+R, then option+3."; wait_enter
    check "option+3 shows workspace 3" [ "$(focused_workspace)" = 3 ]
    check "on the main monitor, from the other one" [ "$(focused_monitor)" = $main ]
    say "Press option+Enter to open a terminal on 3, and keep it focused."; wait_enter
    local window secondary
    window=$(aerospace list-windows --focused --format '%{window-id}')
    [[ $main == $LEFT ]] && secondary=$RIGHT || secondary=$LEFT
    say "Press option+shift+$([[ $secondary == $RIGHT ]] && print R || print E)."; wait_enter
    check "option+shift+letter carries the window to the other monitor's own workspace" [ "$(workspace_of $window)" = "$secondary-S" ]
    check "and focus follows it" [ "$(focused_monitor)" = $secondary ]
    say "Press option+shift+5."; wait_enter
    check "option+shift+5 sends the window to workspace 5" [ "$(workspace_of $window)" = 5 ]
    check "and focus stays where it was" [ "$(focused_monitor)" = $secondary ]
    aerospace close --window-id $window 2>/dev/null
    aerospace workspace --fail-if-noop 1 >/dev/null 2>&1
}

right_cable() {
    mark right-cable
    say "2. One cable"
    local main secondary
    main=$(aerospace list-monitors --format '%{monitor-key} %{monitor-is-main}' | awk '$2 == "true" { print $1 }')
    [[ $main == $LEFT ]] && secondary=$RIGHT || secondary=$LEFT
    windows_on $secondary > "$OUT/secondary-windows.txt"
    numbered_windows > "$OUT/numbered-windows.txt"
    say "Unplug the cable of the monitor WITHOUT the menu bar only."
    wait_until 30 monitors_are "$main " || verdict "the secondary monitor disappears" 0
    sleep 4
    check "the laptop panel stays off with one monitor left" panel_is off
    check "its windows float on the workspace the main monitor shows" windows_float_on_main "$OUT/secondary-windows.txt"
    say "Plug that monitor back in."
    wait_until 30 monitors_are "$LEFT $RIGHT " || verdict "the secondary monitor comes back" 0
    sleep 1
    check "its windows go home" windows_back_home "$OUT/secondary-windows.txt"
    check "workspaces 1-0 kept their windows" [ "$(numbered_windows)" = "$(<$OUT/numbered-windows.txt)" ]
}

both_cables() {
    mark both-cables
    say "3. Both cables (twice)"
    windows_on $LEFT > "$OUT/own-windows.txt"
    windows_on $RIGHT >> "$OUT/own-windows.txt"
    numbered_windows > "$OUT/numbered-windows.txt"
    local round since seconds
    for round in 1 2; do
        since=$EPOCHREALTIME
        say "Round $round: unplug BOTH monitor cables."
        wait_until 30 panel_is on
        sleep 4
        seconds=$(seconds_from_last_monitor_to_panel $since)
        verdict "round $round: the panel lights after the last monitor leaves" $([[ $seconds != never ]] && (( seconds < 2 )) && print 1 || print 0) "${seconds}s"
        if (( round == 1 )); then
            check "the monitors' own windows float on the workspace the laptop shows" windows_float_on_main "$OUT/own-windows.txt"
        fi
        say "Plug both cables back in."
        wait_until 30 monitors_are "$LEFT $RIGHT " || verdict "both monitors come back" 0
        check "round $round: the panel goes off again" wait_until 5 panel_is off
    done
    sleep 1
    check "the monitors' own windows went home" windows_back_home "$OUT/own-windows.txt"
    check "workspaces 1-0 kept their windows" [ "$(numbered_windows)" = "$(<$OUT/numbered-windows.txt)" ]
}

chord() {
    mark chord
    say "4. The chord"
    say "Press ctrl+option+cmd+L."
    check "the chord lights the panel" wait_until 5 panel_is on
    sleep 3
    check "and it stays on" panel_is on
    say "Press ctrl+option+cmd+L again."
    check "the chord turns it off again" wait_until 5 panel_is off
    desk auto
}

lock() {
    mark lock
    say "5. Lock and Touch ID"
    say "Lock the screen with ctrl+cmd+Q, then unlock it with your fingerprint."; wait_enter
    check "the panel is still off after unlocking" panel_is off
    yes_no "Did the fingerprint unlock work?" && verdict "Touch ID with the panel off" 1 || verdict "Touch ID with the panel off" 0
}

crash() {
    mark crash
    say "6. The agent crashes (nothing to do)"
    local before after lines
    lines=$(wc -l < "$DESK_EVENTS")
    before=$(launchctl print gui/$(id -u)/com.mac-setup.desk | awk '/^\tpid =/ { print $3 }')
    kill -9 $before
    sleep 2
    after=$(launchctl print gui/$(id -u)/com.mac-setup.desk | awk '/^\tpid =/ { print $3 }')
    verdict "launchd brings the agent back" $([[ -n $after && $after != $before ]] && print 1 || print 0) "pid $before → ${after:-none}"
    sleep 2
    check "the panel stays off" panel_is off
    check "without switching it on in between" [ -z "$(tail -n +$((lines + 1)) "$DESK_EVENTS" | grep panel-on)" ]
}

overview() {
    mark overview
    say "7. F3"
    say "Focus the monitor WITHOUT the menu bar, press F3 and look at both monitors for a few seconds."; wait_enter
    yes_no "One grid of 1-0 with a letter on the main monitor, and only a letter at the same height on the other?" && verdict "F3 on every monitor" 1 || verdict "F3 on every monitor" 0
    say "Press 4."; wait_enter
    check "a digit goes to the main grid" [ "$(main_workspace)" = 4 ]
    yes_no "Did every Mission Control window close at once?" && verdict "F3 closes everywhere" 1 || verdict "F3 closes everywhere" 0
    aerospace workspace 1 >/dev/null 2>&1
}

trap cleanup EXIT INT TERM
preflight
for step in "${STEPS[@]}"; do
    case $step in
        docked) docked ;;
        right-cable) right_cable ;;
        both-cables) both_cables ;;
        chord) chord ;;
        lock) lock ;;
        crash) crash ;;
        overview) overview ;;
        *) say "unknown step $step" ;;
    esac
done
