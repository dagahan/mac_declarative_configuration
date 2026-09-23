#!/usr/bin/env zsh
set -u
zmodload zsh/datetime
export PATH="/opt/homebrew/bin:$PATH"

typeset -g HERE=${0:A:h} DRY=0 ID="" SCOPE=session
[[ ${1:-} == --dry-run ]] && DRY=1
typeset -g OUT="${MONITOR_PROBE_OUT:-$HOME/.local/state/mac_setup/monitors/$(strftime %Y%m%d-%H%M%S $EPOCHSECONDS)}"
typeset -g EV="$OUT/events.jsonl"
typeset -ga HELPERS
mkdir -p "$OUT"

probe() { swift "$HERE/probe.swift" "$@" 2>>"$OUT/stderr.log" }
hw() { if (( DRY )); then print -r -- "{\"dry\":true}"; else "$@"; fi }
mark() { print -r -- "{\"ts\":$EPOCHREALTIME,\"ev\":\"step\",\"name\":\"$1\"}" >> "$EV" }
say() { print -r -- ""; print -r -- "  $*" }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2" 2>/dev/null }

ask() {
    local key=$1 reply
    shift
    print -rn -- "  $* "
    read -r reply
    reply=${reply//[^A-Za-z0-9 ]/}
    print -r -- "{\"ts\":$EPOCHREALTIME,\"ev\":\"answer\",\"key\":\"$key\",\"value\":\"$reply\"}" >> "$EV"
}

wait_enter() {
    local reply
    print -rn -- "  press Enter "
    read -r reply
}

wait_for() {
    local file=$1 pattern=$2 i
    for i in {1..300}; do
        [[ -f $file ]] && grep -q -- "$pattern" "$file" && return 0
        sleep 0.1
    done
    return 1
}

on_ac() { pmset -g batt | grep -q "AC Power" }

cleanup() {
    trap - EXIT INT TERM
    say "putting everything back"
    [[ -f $OUT/holder.pid ]] && kill -9 $(<$OUT/holder.pid) 2>/dev/null
    rm -f "$OUT/holder.pid"
    if (( ! DRY )); then
        [[ -n $ID ]] && probe panel on "$ID" >> "$OUT/restore.json"
        [[ -f $OUT/kbd-saved.json ]] && probe kbd restore "$OUT/kbd-saved.json" >> "$OUT/restore.json"
    fi
    touch "$OUT/stop"
    sleep 1.5
    pkill -f "$HERE/probe.swift.*(logger|watchdog)" 2>/dev/null
    kill ${HELPERS[@]} 2>/dev/null
    probe panel state > "$OUT/final-state.json"
    probe kbd get > "$OUT/final-kbd.json"
    print -r -- ""
    python3 "$HERE/analyze.py" "$OUT" | tee "$OUT/summary.txt"
    say "results: $OUT"
}

panel_off() {
    local tag=$1
    if [[ $SCOPE == appOnly ]]; then
        if (( DRY )); then print -r -- '{"dry":true,"held":true}' > "$OUT/$tag-hold.json"; return; fi
        probe panel hold appOnly "$ID" "$OUT/holder.pid" > "$OUT/$tag-hold.json" &
        wait_for "$OUT/$tag-hold.json" held
    else
        hw probe panel off session "$ID" > "$OUT/$tag-off.json"
    fi
    sleep 1
}

preflight() {
    say "Monitor tests — about 5 minutes. Stay at the desk: lid open, charger connected."
    say "Keep this window on one of the big monitors. Windows on the laptop screen will be moved to a monitor."
    say "If every screen goes dark: plug a monitor cable back in, or press ctrl+c here. Reopening the lid does not help."
    probe panel state > "$OUT/preflight.json"
    ID=$(field "$OUT/preflight.json" builtin)
    [[ -n $ID ]] || { say "the laptop screen is not on — open the lid and run again"; exit 1 }
    local externals
    externals=$(python3 -c 'import json,sys; print(sum(1 for d in json.load(open(sys.argv[1]))["displays"] if not d["builtin"] and d["active"]))' "$OUT/preflight.json")
    (( externals >= 1 )) || { say "connect at least one monitor first"; exit 1 }
    on_ac || { say "connect the charger first — closing the lid on battery puts the Mac to sleep"; exit 1 }
    print -r -- "$ID" > "$OUT/builtin"
    print -r -- 0 > "$OUT/grace"
    { while :; do touch "$OUT/heartbeat"; sleep 1; done } &
    HELPERS+=($!)
    probe logger "$EV" &
    HELPERS+=($!)
    wait_for "$EV" logger-start || { say "the event logger did not start"; exit 1 }
    probe watchdog "$OUT" "$EV" "$DRY" &
    HELPERS+=($!)
    wait_for "$EV" watchdog-start || { say "the safety watchdog did not start"; exit 1 }
    probe displays > "$OUT/displays-before.json"
    probe kbd get > "$OUT/kbd-before.json"
    probe touchid can > "$OUT/touchid-before.json"
}

b1() {
    mark B1.begin
    say "B1 — the laptop screen turns off for a few seconds."
    if (( DRY )); then
        print -r -- '{"dry":true,"held":true}' > "$OUT/B1-hold.json"
    else
        probe panel hold appOnly "$ID" "$OUT/holder.pid" > "$OUT/B1-hold.json" &
        wait_for "$OUT/B1-hold.json" held || { say "could not turn the laptop screen off"; mark B1.end; return }
    fi
    sleep 2
    probe panel state > "$OUT/B1-state.json"
    ask B1.dark "Is the laptop screen completely dark — no picture and no glow? [y/n]"
    mark B1.kill
    (( DRY )) || kill -9 $(<"$OUT/holder.pid") 2>/dev/null
    sleep 6
    rm -f "$OUT/holder.pid"
    probe panel state > "$OUT/B1-after.json"
    mark B1.end
}

b2() {
    mark B2.begin
    say "B2 — the laptop screen turns off again, then back on."
    hw probe panel off session "$ID" > "$OUT/B2-off.json"
    sleep 2
    probe panel state > "$OUT/B2-state.json"
    mark B2.enable
    hw probe panel on "$ID" > "$OUT/B2-on.json"
    sleep 2
    probe panel state > "$OUT/B2-after.json"
    mark B2.end
}

b3() {
    mark B3.begin
    panel_off B3
    say "B3 — the laptop screen is off. Now the fingerprint sensor, the microphone and the keyboard."
    probe touchid can > "$OUT/B3-touchid-can.json"
    say "Touch the fingerprint sensor when macOS asks."
    hw probe touchid ask > "$OUT/B3-touchid.json"
    local index
    index=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -n 's/.*\[\([0-9]*\)\] MacBook Pro Microphone.*/\1/p' | head -1)
    say "Microphone: after Enter, say a few words for 2 seconds. If macOS asks for microphone access, allow it."
    wait_enter
    if [[ -z $index ]]; then
        print -r -- "no built-in microphone found" > "$OUT/B3-mic.txt"
    elif (( DRY )); then
        print -r -- "dry" > "$OUT/B3-mic.txt"
    else
        ffmpeg -hide_banner -nostats -f avfoundation -i ":$index" -t 2 -af volumedetect -f null - > "$OUT/B3-mic.txt" 2>&1
    fi
    hw probe kbd off "$OUT/kbd-saved.json" > "$OUT/B3-kbd-off.json"
    ask B3.typed "Type the word desk on the LAPTOP keyboard, then press Enter:"
    ask B3.backlight "While you typed, did the laptop keyboard light stay off? [y/n]"
    probe kbd get > "$OUT/B3-kbd.json"
    mark B3.end
}

b4() {
    mark B4.begin
    say "B4 — turn the RIGHT monitor off with its own power button. Count to three. Turn it back on."
    say "When it shows a picture again:"
    wait_enter
    mark B4.end
    probe displays > "$OUT/B4-displays.json"
    probe kbd get > "$OUT/B4-kbd.json"
}

b5() {
    mark B5.begin
    say "B5 — after Enter the screens go to sleep. Keep your hands off for 10 seconds,"
    say "then wake them by moving the mouse. If macOS asks you to unlock, use the fingerprint sensor."
    wait_enter
    mark B5.sleep
    hw pmset displaysleepnow > /dev/null
    sleep 3
    say "Awake again?"
    wait_enter
    mark B5.end
    ask B5.unlock "Did you unlock with the fingerprint? [y = yes, n = it failed, s = there was no lock screen]"
    probe displays > "$OUT/B5-displays.json"
    probe kbd get > "$OUT/B5-kbd.json"
}

b6() {
    probe panel state > "$OUT/B6-before.json"
    [[ $(field "$OUT/B6-before.json" active) == True ]] && panel_off B6
    mark B6.begin
    say "B6 — unplug BOTH monitor cables from the Mac now."
    say "The laptop screen should light up within a few seconds. When it does:"
    wait_enter
    mark B6.unplugged
    probe panel state > "$OUT/B6-unplugged.json"
    say "Plug both cables back in. When both monitors show a picture:"
    wait_enter
    mark B6.replugged
    sleep 2
    probe displays > "$OUT/B6-displays.json"
    probe kbd get > "$OUT/B6-kbd.json"
    mark B6.end
}

b7() {
    if ! on_ac; then
        say "B7 skipped — the charger is not connected, and closing the lid would put the Mac to sleep."
        mark B7.skipped
        return
    fi
    mark B7.begin
    panel_off B7
    say "B7 — close the lid fully, wait 3 seconds, open it again. Then:"
    wait_enter
    mark B7.end
    probe panel state > "$OUT/B7-state.json"
    ask B7.lit "After you opened the lid, did the laptop screen light up? [y/n]"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

preflight
b1
b2
SCOPE=$(python3 "$HERE/analyze.py" "$OUT" --scope)
say "using the $SCOPE setting for the rest of the session"
b3
b4
b5
b6
b7
