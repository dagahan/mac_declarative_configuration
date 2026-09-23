import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])


def load(name):
    try:
        return json.loads((out / name).read_text())
    except (OSError, ValueError):
        return None


def text(name):
    try:
        return (out / name).read_text()
    except OSError:
        return ""


events = []
for line in text("events.jsonl").splitlines():
    try:
        events.append(json.loads(line))
    except ValueError:
        pass
events.sort(key=lambda e: e["ts"])

steps = {e["name"]: e["ts"] for e in events if e["ev"] == "step"}
answers = {e["key"]: e["value"] for e in events if e["ev"] == "answer"}
states = [e for e in events if e["ev"] in ("state", "logger-start")]
enables = [e for e in events if e["ev"] in ("watchdog-enable", "watchdog-would-enable")]


def panel_on(state):
    return any(d["builtin"] and d["active"] for d in state["displays"])


def externals(state):
    return [d for d in state["displays"] if not d["builtin"] and d["online"] and d["mirrors"] == 0 and d.get("real", d["serial"] != 0)]


def window(a, b):
    return [s for s in states if a <= s["ts"] <= b]


def first(cond, after, before=None):
    return next((s for s in states if s["ts"] >= after and (before is None or s["ts"] <= before) and cond(s)), None)


def last_before(ts):
    earlier = [s for s in states if s["ts"] <= ts]
    return earlier[-1] if earlier else None


def helped(a, b):
    return [e for e in enables if a <= e["ts"] <= b]


def seconds(a, b):
    return f"{b - a:.2f} s"


def came_back(after, until=None):
    current = last_before(after)
    if current and panel_on(current):
        return current, "was never off"
    back = first(panel_on, after, until)
    if not back:
        return None, "did not come back"
    who = "the watchdog" if helped(after, back["ts"]) else "macOS by itself"
    return back, f"came back after {seconds(after, back['ts'])}, brought back by {who}"


def app_only_works():
    held = load("B1-state.json")
    if not held or held.get("active", True) or "B1.kill" not in steps:
        return False
    back = first(panel_on, steps["B1.kill"])
    return back is not None and not helped(steps["B1.kill"], back["ts"])


if "--scope" in sys.argv:
    print("appOnly" if app_only_works() else "session")
    sys.exit()

lines = []


def report(tag, message):
    lines.append(f"  {tag:3} {message}")


def not_run(tag):
    report(tag, "not run")


before = load("displays-before.json") or {"displays": []}
before_by_serial = {d["serial"]: d for d in before["displays"]}
before_externals = externals(before)

if "B1.begin" in steps:
    held = load("B1-state.json") or {}
    off = held.get("active") is False
    result = came_back(steps["B1.kill"])[1] if "B1.kill" in steps else "was never released"
    report("B1", f"app-only: panel {'off' if off else 'STAYED ON'}; you saw it dark: {answers.get('B1.dark', '?')}; "
                 f"after the holder was killed the panel {result}")
else:
    not_run("B1")

if "B2.begin" in steps:
    went = first(lambda s: not panel_on(s), steps["B2.begin"], steps.get("B2.enable"))
    back = first(panel_on, steps["B2.enable"]) if "B2.enable" in steps and went else None
    report("B2", f"session: {'off after ' + seconds(steps['B2.begin'], went['ts']) if went else 'panel STAYED ON'}; "
                 f"turned back on {'after ' + seconds(steps['B2.enable'], back['ts']) if back else 'NEVER'}")
else:
    not_run("B2")

if "B3.begin" in steps:
    can = load("B3-touchid-can.json") or {}
    touch = load("B3-touchid.json") or {}
    mic = text("B3-mic.txt")
    mean = re.search(r"mean_volume: ([-\d.]+) dB", mic)
    peak = re.search(r"max_volume: ([-\d.]+) dB", mic)
    keyboard = next((k for k in load("B3-kbd.json") or [] if k.get("builtIn")), {})
    report("B3", f"Touch ID available={can.get('available')} touch passed={touch.get('passed')}; "
                 f"mic mean={mean.group(1) + ' dB' if mean else mic.strip()[:40]!s} peak={peak.group(1) + ' dB' if peak else '-'}; "
                 f"typed={answers.get('B3.typed')!r}; light stayed off (you)={answers.get('B3.backlight', '?')}, "
                 f"measured brightness={keyboard.get('brightness')} auto={keyboard.get('auto')}")
else:
    not_run("B3")

if "B4.begin" in steps and "B4.end" in steps and before_externals:
    a, b = steps["B4.begin"], steps["B4.end"]
    right = max(before_externals, key=lambda d: d["x"])
    present = lambda s: any(d["serial"] == right["serial"] for d in externals(s))
    gone = first(lambda s: not present(s), a, b)
    back = first(present, gone["ts"], b) if gone else None
    lit = any(panel_on(s) for s in window(a, b)) and not panel_on(last_before(a) or {"displays": []})
    after = {d["serial"]: d for d in (load("B4-displays.json") or {"displays": []})["displays"]}
    same = right["serial"] in after and (after[right["serial"]]["x"], after[right["serial"]]["y"]) == (right["x"], right["y"])
    blink = f"disconnected for {seconds(gone['ts'], back['ts'])}" if gone and back else ("disconnected and never came back" if gone else "never disconnected")
    report("B4", f"right monitor {blink}; panel lit meanwhile: {lit}; same serial and position after: {same}; "
                 f"id before {right['id']} after {after.get(right['serial'], {}).get('id')}")
else:
    not_run("B4")

if "B5.sleep" in steps and "B5.end" in steps:
    a, b = steps["B5.sleep"], steps["B5.end"]
    counts = [len(externals(s)) for s in window(a, b)]
    asleep = any(d["asleep"] for s in window(a, b) for d in s["displays"])
    dropped = counts and min(counts) < len(before_externals)
    lit = first(panel_on, a, b)
    locks = [e["name"] for e in events if e["ev"] == "lock" and a <= e["ts"] <= b]
    report("B5", f"monitors reported asleep: {asleep}; monitors disconnected during sleep: {bool(dropped)} "
                 f"(fewest seen {min(counts) if counts else '-'}); panel lit: {'yes, ' + ('by the watchdog' if helped(a, lit['ts']) else 'by macOS') if lit else 'no'}; "
                 f"lock events {locks}; unlock with fingerprint: {answers.get('B5.unlock', '?')}")
else:
    not_run("B5")

if "B6.begin" in steps and "B6.unplugged" in steps:
    a = steps["B6.begin"]
    empty = first(lambda s: not externals(s), a)
    result = ("the panel " + came_back(empty["ts"])[1]) if empty else "the monitors never all disappeared"
    after = load("B6-displays.json") or {"displays": []}
    rows = []
    for d in externals(after):
        old = before_by_serial.get(d["serial"])
        rows.append(f"serial {d['serial']}: " + ("NEW" if not old else f"id {old['id']}→{d['id']}, position {'same' if (old['x'], old['y']) == (d['x'], d['y']) else 'MOVED'}"))
    main_after = next((d["serial"] for d in after["displays"] if d["main"]), None)
    main_before = next((d["serial"] for d in before["displays"] if d["main"]), None)
    report("B6", f"unplugged: {result}; after replug: {'; '.join(rows) or 'no monitors'}; "
                 f"main display {'same' if main_after == main_before else f'changed {main_before}→{main_after}'}")
else:
    not_run("B6")

if "B7.begin" in steps:
    a, b = steps["B7.begin"], steps["B7.end"]
    closed = any(s.get("lidClosed") for s in window(a, b))
    opened = first(lambda s: s.get("lidClosed") is False, (first(lambda s: s.get("lidClosed"), a, b) or {"ts": b})["ts"], b)
    lit = first(panel_on, opened["ts"], b) if opened else None
    report("B7", f"lid closed seen: {closed}; panel lit after opening: "
                 f"{('yes, by ' + ('the watchdog' if helped(opened['ts'], lit['ts']) else 'macOS')) if lit else 'no'}; you: {answers.get('B7.lit', '?')}")
elif "B7.skipped" in steps:
    report("B7", "skipped — no charger")
else:
    not_run("B7")

light = []
for name in ["kbd-before", "B3-kbd", "B4-kbd", "B5-kbd", "B6-kbd", "final-kbd"]:
    keyboard = next((k for k in load(name + ".json") or [] if k.get("builtIn")), None)
    if keyboard:
        light.append(f"{name}={keyboard['brightness']:.2f}{'/auto' if keyboard['auto'] else ''}")
report("kbd", "light across the session: " + ", ".join(light))

final = load("final-state.json") or {}
report("end", f"panel on at the end: {final.get('active')}; watchdog actions: {[e.get('reason') for e in enables]}")

print("\n".join(lines))
