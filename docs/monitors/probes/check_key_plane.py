#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
aerospace_toml = repo / "config/aerospace/aerospace.toml"
karabiner_json = repo / "config/karabiner/karabiner.json"

letters = "sdfgxcvb"
digits = "0123456789"
expected_in_both_modes = (
    {f"alt-{letter}": f"focus-monitor letter:{letter}" for letter in letters}
    | {f"alt-shift-{letter}": f"move-node-to-monitor --focus-follows-window letter:{letter}" for letter in letters}
    | {f"alt-{digit}": f"workspace {digit}" for digit in digits}
    | {f"alt-shift-{digit}": f"move-node-to-workspace {digit}" for digit in digits}
    | {"alt-esc": "pin-monitor off"}
)
expected_in_main_only = {"alt-shift-e": "smart-open Finder"}
must_be_gone = {"alt-shift-tab"}
enabled_system_shortcuts = {"ctrl-alt-space"}
expected_top_level = {
    "per-monitor-workspaces": '["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]',
    "persistent-workspaces": "[]",
    "floating-workspaces": '["1"]',
    "unplugged-monitor-grace-seconds": "3",
}


def parse_bindings(text):
    modes, top_level, duplicates = {}, {}, []
    section = None
    for line in text.splitlines():
        stripped = line.split("#", 1)[0].strip() if not line.strip().startswith(("'", '"')) else line.strip()
        header = re.fullmatch(r"\[(.+)\]", stripped)
        if header:
            section = header.group(1)
            continue
        pair = re.fullmatch(r"([A-Za-z0-9.-]+)\s*=\s*(.+)", stripped)
        if not pair:
            continue
        key, value = pair.group(1), pair.group(2).strip().strip("'\"")
        mode = re.fullmatch(r"mode\.(\w+)\.binding", section or "")
        if mode:
            bindings = modes.setdefault(mode.group(1), {})
            if key in bindings:
                duplicates.append(f"{mode.group(1)}: {key}")
            bindings[key] = value
        elif section is None:
            top_level[key] = pair.group(2).strip()
    return modes, top_level, duplicates


def karabiner_chords():
    names = {"option": "alt", "left_option": "alt", "right_option": "alt",
             "shift": "shift", "left_shift": "shift", "right_shift": "shift",
             "command": "cmd", "left_command": "cmd", "right_command": "cmd",
             "control": "ctrl", "left_control": "ctrl", "right_control": "ctrl"}
    order = ["cmd", "alt", "ctrl", "shift"]
    chords = {}
    rules = json.loads(karabiner_json.read_text())["profiles"][0]["complex_modifications"]["rules"]
    for rule in rules:
        for manipulator in rule["manipulators"]:
            source = manipulator.get("from", {})
            key = source.get("key_code")
            if not key:
                continue
            modifiers = {names.get(m, m) for m in source.get("modifiers", {}).get("mandatory", [])}
            chord = "-".join([m for m in order if m in modifiers] + [key.replace("spacebar", "space")])
            chords[chord] = rule["description"]
    return chords


def main():
    modes, top_level, duplicates = parse_bindings(aerospace_toml.read_text())
    problems = [f"bound twice in {d}" for d in duplicates]
    for mode in ("main", "floating"):
        bindings = modes.get(mode, {})
        for key, command in expected_in_both_modes.items():
            if bindings.get(key) != command:
                problems.append(f"{mode}: {key} is {bindings.get(key)!r}, expected {command!r}")
        for key in must_be_gone & bindings.keys():
            problems.append(f"{mode}: {key} must be gone")
    for key, command in expected_in_main_only.items():
        if modes.get("main", {}).get(key) != command:
            problems.append(f"main: {key} is {modes.get('main', {}).get(key)!r}, expected {command!r}")
    for key, value in expected_top_level.items():
        if top_level.get(key) != value:
            problems.append(f"top level: {key} is {top_level.get(key)!r}, expected {value!r}")
    taken_by_karabiner = karabiner_chords()
    added_by_this_design = expected_in_both_modes.keys() | expected_in_main_only.keys()
    for mode, bindings in modes.items():
        for key in bindings.keys() & added_by_this_design:
            if key in taken_by_karabiner:
                problems.append(f"{mode}: {key} collides with Karabiner rule {taken_by_karabiner[key]!r}")
            if key in enabled_system_shortcuts:
                problems.append(f"{mode}: {key} collides with an enabled system shortcut")
    for problem in problems:
        print(f"FAIL {problem}")
    bound = sum(len(b) for b in modes.values())
    print(f"{'ok' if not problems else 'FAILED'}: {bound} bindings in {len(modes)} modes, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
