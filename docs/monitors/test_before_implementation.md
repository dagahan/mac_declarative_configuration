# Tests before implementation

These run before any code changes. They do four things:

- prove the ground the implementation stands on (the fork builds and its tests pass, the repo is
  clean);
- turn the recorded session into fixtures the code must match;
- write down, as tables, the behaviour the unit tests will assert;
- re-measure the one thing that failed last time, unplugging both monitors, using the exact rule
  the helper will use.

Architecture: [new_architecture.md](new_architecture.md). Measured facts:
[test_before_writing_architecture.md](test_before_writing_architecture.md).

## Gates

| Result | Unlocks |
|---|---|
| P1–P2 pass | Chapters 1–7 of [implementation.md](implementation.md) (AeroSpace fork and config) |
| P3 written, H1 passes | Chapters 8–9 (the desk helper) |
| All of the above | Chapter 10 (the attended end-to-end run) |

## Part A — headless

### P1 — the fork's baseline

Run `./swift-test.sh` in `vendor/AeroSpace` at its current commit (`1eebf28a`), and build the
release product the way `recipes/aerospace.zsh` does. Record how many tests run and how long the
build takes.

**Passes when** every existing test passes and the build succeeds. Every later chapter compares
against this, so a failure here means the fork was already broken before this work started.

### P2 — a clean repo to commit into

`mac_setup` has uncommitted work of yours: the InputLock app, and edits to
`config/karabiner/karabiner.json`, `units/activate.zsh`, `software.toml` and `engine/core.zsh`.
This plan edits `karabiner.json` and `units/activate.zsh` too. Commits here are made per path,
so without this step your in-progress InputLock edits would end up inside my commits.

**Passes when** those files are committed, by you or as a separate commit I make at your
request, and `git status` shows only `docs/monitors/`.

### P3 — the desk rule, replayed against the real session

`~/.local/state/mac_setup/monitors/20260923-172345/events.jsonl` is copied into the helper's
tests as a fixture. The helper's rule is a pure function of display snapshots, time and any
manual override. Fed the recorded snapshots, it must decide:

| Time (s) | What the Mac showed | Decision |
|---|---|---|
| 0.1 | Both monitors, panel on | Off, once 1.5 s stable (at 1.6) |
| 201.4–204.3 | Both monitors online but asleep and inactive | Stay off |
| 222.5 | Only the right monitor | Stay off |
| 226.6 | Only the stand-in (serial 0, `unkn`/`virt`) | **On, on this tick** |
| 247.7 | Left monitor back | Off at 249.2 (1.5 s stable) |
| 258.9 | Stand-in again | **On, on this tick** |
| 266.1 | Left monitor back | Off at 267.6 |
| 274.0 | Both monitors | Stay off |
| 292.8–296.5 | Lid closed and reopened, monitors present | Stay off |

Also:
- a manual "on" at 60 s holds until 222.5, where the set of serials changes;
- a manual "off" pressed while only the stand-in exists is refused.

**Passes when** the expected decisions above are recorded as the fixture's assertions. The test
runs in chapter 8, against the real code.

### P4 — letters from real geometry

Recorded frames and the letters they must produce:

| Monitors (key @ x,y, w×h) | Letters |
|---|---|
| `builtin` @ 0,0 1512×982 · `3996` @ −533,−1440 · `39260` @ 2027,−1440 | 3996 D, 39260 F, builtin C |
| `39260` @ 0,0 · `3996` @ −2560,0 (panel off) | 3996 D, 39260 F |
| `3996` @ 0,0 alone | 3996 D |
| `builtin` @ 0,0 alone | builtin D |
| stand-in id 18 @ 0,0 alone | none |

**Passes when** the table is recorded as fixtures for chapter 3's tests. The probe's letter
function already produced row 1 on the live desk (A1).

### P5 — unplug and replug, as scenarios

These become chapter 5's unit tests. They run against a multi-monitor test double (chapter 1),
with D = `3996`, F = `39260`, and a grace period of 3 s.

| # | Scenario | Expected |
|---|---|---|
| S1 | F disappears and returns after 2 s | Nothing moves; F shows the workspace it had |
| S2 | F disappears for good | At 3 s, F-3's tiled windows sit in one accordion column at the edge of D-3; D-3's own tiles keep their sizes; each visitor's home is (39260, 3) |
| S3 | F returns after S2 | The visitors go back to F-3 in their old order; D-3 looks as it did before S2 |
| S4 | During S2 a visitor is moved by hand to D-5; then F returns | That window stays on D-5; the others go home |
| S5 | F-1 (floating) has windows when F disappears | They land on D-1 with their frames clamped onto D; they return with their frames |
| S6 | Undock: D and F disappear, the panel appears | Windows whose home is `builtin` come back from D at once; at 3 s, D-n and F-n both land in builtin-n |
| S7 | For 1.2 s only the stand-in exists, then the panel appears | Nothing is merged into the stand-in; the stand-in owns no workspaces |
| S8 | A monitor with an unknown serial appears | Ten empty workspaces, showing its own 1; nothing moves to it |
| S9 | AeroSpace restarts while S2's visitors are away | Homes survive; S3 still works after the restart |
| S10 | Focus on F: `workspace 3` / a window on D: `move-node-to-workspace 3` | 39260-3 / 3996-3 |
| S11 | The main display flips: the panel returns and every origin shifts | Every monitor keeps its visible workspace; nothing merges |

**Passes when** the table is recorded. Chapter 5 turns each row into a test.

### P6 — the key plane after the config is written

A small check script parses the new `aerospace.toml`. It asserts that:
- every key in the architecture's §5 is bound, in both `mode.main` and `mode.floating`;
- no key is bound twice;
- nothing collides with a Karabiner rule or the one enabled system shortcut
  (ctrl+option+space, A6);
- `option+shift+Tab` is gone.

It is specified here and runs in chapter 7.

### P7 — a layout snapshot that restores

Before every AeroSpace restart:
1. Record `aerospace list-windows --all --format '%{window-id}|%{app-name}|%{workspace}'` and
   the focused workspace.
2. After the restart, put every window back with `move-node-to-workspace --window-id`.

Restarts have scattered windows before, so this runs around every restart.

**Passes when** a capture-and-restore round trip on the running AeroSpace leaves every window
where it was. AeroSpace isn't running right now, so this runs at the start of chapter 4, after
`mac workspace up`.

## Part B — attended, about 2 minutes

### H1 — unplug both monitors with the fixed rule (required before chapter 8)

The probe watchdog now uses exactly the helper's definition of a real monitor, with no grace
period. `session.zsh` gets a `--only B6` switch that runs just the preflight and the unplug step.

- **Expect:** after the second cable is out, the panel lights within about 1.5 s: a 0.1 s poll
  plus the 0.85 s switch. With one cable out, the panel stays off.
- **Observe:** whether the stand-in display disappears once the panel is lit. The design doesn't
  depend on it, but S7 is written as if it might not.

**Passes when** the panel lights in under 2 s every time, over two unplugs, and one monitor
alone never lights it.

### H2 — microphone with speech (optional, 10 s)

Record 3 s while you speak, with the panel off. B3 only captured room noise.

**Passes when** the peak is clearly above B3's −48 dB.

### H3 — does a disabled panel survive logout? (optional)

1. With both monitors connected, turn the panel off with session scope.
2. Log out and back in.
3. Check the panel.

Both answers are covered: the login agent runs `mac workspace down`, and down turns the panel on.
This is only for knowing. Logging out closes every app, so run it only if you want the answer.

## Results

Filled in as the tests run.
