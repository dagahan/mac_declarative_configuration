# Implementation

> **Superseded on Oct 10, 2026.** Workspaces 1-0 are now shared and shown only on the main
> display; every other display owns one floating workspace `<display-id>-S`. The top-row
> letters are E R T Y, and pin-monitor is gone. `config/aerospace/aerospace.toml` and
> `probes/e2e.zsh` describe the current behaviour.

This is the step-by-step build of [new_architecture.md](new_architecture.md), in chapters.

- Each chapter ends with a test that drives the real thing.
- Each chapter is committed on its own once its test passes. Commits are path-scoped, so none of
  your other edits ride along.
- Nothing is pushed until chapter 10 passes. Then the fork (`origin/mac-setup`) and mac_setup
  (branch `refactor/declarative-engine`) are pushed once each.

**After your go-ahead, chapters run unattended, except where noted:**
- **Attended:** H1 before chapter 8, and chapter 10. Each needs you at the desk and is announced
  before it starts.
- **Screen changes:** AeroSpace restarts in chapters 4 and 7, and the laptop panel turns off and
  on in chapter 9. I announce each one before doing it. The window layout is captured before
  every AeroSpace restart and restored after it (P7).

Every step names the existing code it extends, in keeping with "reuse before writing new code".

## Chapter 0 — Before anything

1. Run Part A of [test_before_implementation.md](test_before_implementation.md): P1 and P2.
   P3–P5 are recorded as fixtures and scenario tables.
2. P2 needs you: your uncommitted InputLock work has to be committed first, because this plan also
   edits `karabiner.json` and `units/activate.zsh`.
3. Record the results in that file.

## Chapter 1 — Fork: a test double with several monitors

- `Sources/AppBundle/model/Monitor.swift:98-110`: in unit tests, `monitors` and `mainMonitor`
  read a settable list. It defaults to today's single `testMonitor`, so every existing test is
  unchanged.
- `Sources/AppBundleTests/testUtil.swift` gains `setTestMonitors(...)`, taking key, frame and a
  built-in or stand-in flag, plus a helper that runs the same `gcMonitors()` path a real refresh
  does.
- **Test:** the full suite passes with the P1 count, plus one new test that swaps in two monitors
  and back.

## Chapter 2 — Fork: monitor identity

- Add `key` (`builtin` or the serial) and `isStandIn` (serial 0 with `unkn`/`virt`) to
  `MonitorImpl`. Read them from the screen's `NSScreenNumber`.
- `gcMonitors()` (`tree/Workspace.swift:136`) compares the **set of keys** instead of the count.
- `rearrangeWorkspacesOnMonitors()` (`:166`) maps old screens to new ones by key first, and falls
  back to the nearest point only for unknown keys.
- `list-monitors` gains a `%{monitor-key}` format variable (`ListMonitorsCommand.swift`).
- **Test:** unit test S11 (the main display flips and every origin shifts). Then e2e on the desk:
  `aerospace list-monitors --format '%{monitor-key}'` prints `3996`, `39260` and `builtin` in
  their places.

## Chapter 3 — Fork: letters

- A row-major letter function over real monitors (the rows and table in architecture §3).
- A new `.letter(Character)` case in `MonitorDescription`, parsed from `letter:x` in
  `parseMonitorDescription`, and resolved in `resolveMonitor` (`model/MonitorDescriptionEx.swift`).
- A `%{monitor-letter}` format variable.
- **Test:** P4's five fixtures as unit tests. Then e2e: `aerospace focus-monitor letter:f`
  focuses the right monitor, and the mouse moves to its centre through the existing
  `on-focused-monitor-changed`.

## Chapter 4 — Fork: workspaces per monitor

- **Config:** a `per-monitor-workspaces` key (`config/parseConfig.swift`, alongside
  `floating-workspaces` at `:153`).
- **Naming and ownership:** `<key>-<n>` workspaces are created per known monitor.
  `forceAssignedMonitor` (`tree/WorkspaceEx.swift:54`) returns the owner while it's connected.
  The stand-in owns nothing.
- **Relative resolution:** a bare local number resolves against a monitor:
  - `WorkspaceCommand` uses the focused monitor;
  - `MoveNodeToWorkspaceCommand` uses the window's monitor.

  Full names pass through unchanged.
- **Stub:** `getStubWorkspace` (`tree/Workspace.swift:16`) prefers the monitor's own previous
  workspace, then its own `1`.
- **Floating by local number:** the four call sites `MinimizeGuard.swift:54`,
  `BordersSync.swift:10`, `HotkeyBinding.swift:65` and `MissionControl.swift:147`.
- **Format variables:** none needed; `%{workspace}` prints the full name.
- **Test:** unit test S10, plus startup (every monitor on its own floating 1). Then e2e:
  1. `mac workspace up` (P7 capture first; **AeroSpace restarts**).
  2. Each monitor shows its own 1 and nothing retiles.
  3. `aerospace workspace 3` with F focused lands on `39260-3`, and with D focused on `3996-3`.
  4. Restore the layout.

## Chapter 5 — Fork: unplugging and replugging

- **Grace:** an `unplugged-monitor-grace-seconds` config key, default 3. A loss is noted with key, frame and
  time. A single timer re-runs the check when the grace period ends.
- **Merge:**
  - Tiled windows go into one accordion container appended to the target workspace's root
    tiling container. This reuses `TilingContainer` and the accordion layout that already exists.
  - Floating windows keep their frames, clamped by the existing `Floating frames` code.
  - The target is the nearest real monitor.
- **Home:** each moved window gets `home = (key, n)`, which is added to `SavedWindow`
  (`persistence/RestoreState.swift:12`) as an optional field so old state files still load.
- **Return:** when a key reappears, the windows whose home is that key go back in their saved
  order.
- **Your move clears home:** at the single place a window's workspace changes because of a
  command or a drag.
- **Test:** S1–S9 as unit tests against the chapter 1 double. The real desk comes in chapter 10.

## Chapter 6 — Fork: pin, menu-bar text, F3 on every monitor

- **Pin:**
  - `FocusMonitorCommand` spots a second request for the same letter within 300 ms.
  - A small `pin-monitor <letter|off>` command follows the pattern of the existing commands in
    `command/impl/`.
  - `MoveNodeToWorkspaceCommand` honours an active pin.
- **Menu bar:** `TrayMenuModel` (`ui/TrayMenuModel.swift:27-60`) shows `D3 F1`, with the focused
  monitor and any pin marked.
- **F3:**
  - `MissionControl.show()` (`ui/MissionControl.swift:61`) builds one panel per real monitor
    instead of one on `NSScreen.main`. Each panel shows its monitor's letter and ten workspaces.
  - Arrow keys work on the focused monitor's panel. A click switches the monitor it was made on.
  - The existing watchdog and hotkey suspension are shared across all panels.
- **Test:** unit tests for pin resolution and the menu-bar text. F3 is checked by eye in chapter
  10.

## Chapter 7 — mac_setup: the AeroSpace config

- **`config/aerospace/aerospace.toml`, in both `mode.main` and `mode.floating`:**
  - `option+S D F G X C V B` → `focus-monitor letter:…`;
  - `option+shift+…` → `move-node-to-monitor --focus-follows-window letter:…`;
  - `option+Esc` → `pin-monitor off`;
  - Finder moves to `option+shift+E`;
  - `option+shift+Tab` is removed.
- **Top-level keys:**
  - `per-monitor-workspaces = ['1',…,'0']`
  - `unplugged-monitor-grace-seconds = 3`
  - `floating-workspaces = ['1']`
  - `persistent-workspaces = []`
- **Test:**
  1. The P6 key-plane script.
  2. `mac sync aerospace` builds and installs the fork.
  3. `mac workspace reload`, with P7 around it (**AeroSpace restarts**).
  4. `mac do hotkeys` shows the new bindings as live.
- **Commit:** the config plus the `vendor/AeroSpace` submodule bump in mac_setup. The fork's own
  commits are already in place from chapters 1–6.

## Chapter 8 — The desk helper (only after H1 passes)

`apps/Desk` is laid out like `apps/InputLock`, reusing its structure:

- `main.swift`: agent versus command;
- `Command.swift`: distributed notifications to the agent, and doing the safe action itself when
  the agent is gone;
- `StatusFile.swift`: state under `$XDG_STATE_HOME/mac_setup/desk/`.

New files carry over calls already proven by `docs/monitors/probes/probe.swift`:

| File | Contents |
|---|---|
| `Displays.swift` | The real-monitor test |
| `Panel.swift` | Session-scoped on/off; the remembered panel id |
| `Keyboard.swift` | Keyboard-light save, zero and restore |
| `Rule.swift` | The pure decision function: panel on immediately when no real monitors; off after 1.5 s stable; the manual override until the set of serials changes; refusing "off" with no monitors |
| `Agent.swift` | 100 ms evaluation on its own dispatch queue plus the screen-parameters notification; reassert the light after wake; check the private call at start and stay a plain laptop if it's missing |

The `mac desk` verbs are `on | off | toggle | auto | status`; launchd runs `mac-desk agent` and `mac-desk rescue`. A test target runs P3's
replay.

- **Test:**
  1. `swift test`: the replay matches P3's table, plus rule unit tests for the override.
  2. Build through the recipe.
  3. Headless `mac desk status` with the agent stopped and then running.

  The panel isn't touched in this chapter.

## Chapter 9 — mac_setup: declaring and wiring the helper

- **`units/desk.zsh`:**
  - `build desk from=apps/Desk recipe=recipes/desk.zsh …`, installed as the plain binary `~/.local/libexec/mac-desk`, outside PATH;
  - `file` resources for `config/launchd/desk.plist` (KeepAlive, ThrottleInterval 1) and
    `config/launchd/desk-rescue.plist` (StartInterval 5, `mac-desk rescue`), both placed under
    `~/.config/mac_setup/launchd/`.
- **`recipes/desk.zsh`:**
  - `build` (the same shape as `recipes/inputlock.zsh`);
  - `up`: bootstrap both jobs;
  - `down`: `mac desk on`, then boot out both.
- **`units/activate.zsh`:** `run desk check='zsh recipes/desk.zsh check' apply='zsh recipes/desk.zsh up' revert='zsh recipes/desk.zsh down'`.
- **`config/karabiner/karabiner.json`:** `ctrl+option+cmd+L` → `~/.local/libexec/mac-desk toggle`.
- **Test** (**the laptop panel turns off and on here; announced first**):
  1. `mac lint` and `mac check`.
  2. `mac workspace up` on a pty. Both jobs are loaded, and the panel goes off about 1.5 s later
     with the keyboard light at 0.
  3. `kill -9` the agent. It's back within about 2 s and the panel stays off.
  4. `mac workspace down` on a pty. The panel is on, the keyboard light is restored, both jobs are
     unloaded, and `mac desk status` says the agent is gone.
  5. `mac workspace up` again, to leave you where you were.

## Chapter 10 — End to end on the real desk (attended, about 5 minutes)

A guided script, `docs/monitors/probes/e2e.zsh`, built like `session.zsh`, walks through this
with you. Every check reads `aerospace list-windows`, `list-monitors` and `mac desk status`; nothing is
judged by eye except F3.

1. **Docked:** the panel is off, and `option+D` and `option+F` focus the right monitors. A roll
   `option: F, 3` lands on F's 3; `option+shift: D, 5` carries a window to D's 5.
2. **Right cable out:** after 3 s, F's windows sit as one column on D's same numbers.
   **Back in:** they return in order (S2, S3).
3. **Both cables out:** the panel lights in about 1 s. The laptop's own windows are home at once,
   and D's and F's join by number at 3 s (S6). **Back in:** the monitors take back their
   windows, the panel goes off after 1.5 s, and the laptop's windows join D.
4. **The chord:** it turns the panel on and off. The override holds until a cable changes.
5. **Sleep and wake:** the panel stays off, and the fingerprint unlock works.
6. **`kill -9` the agent:** it restarts, and nothing flickers.
7. **F3:** one panel per monitor, and a click on F's panel switches F. You look for about 20 s.

**Passes when** every step matches. Then push the fork and mac_setup once each.

## Status (2026-09-23)

Chapters 0–9 are built, tested and committed. Chapter 10 needs you at the desk:
`docs/monitors/probes/e2e.zsh`. Nothing is pushed yet; both repos are pushed once it passes.

| Chapter | Result | Commit |
|---|---|---|
| 0 | P1: the fork's own suite crashed in `CloseCommandTest` before any change (it assumed every window is a real Mac app). Fixed; 384 tests pass. P2: your uncommitted work committed as five commits. | fork `a478b64f`; mac_setup `7464dee`…`6fd852d` |
| 1 | Monitors carry a key; tests plug several monitors | fork `1e1113b6` |
| 2 | Workspaces follow monitors by key; S11 passes | fork `dc66a027` |
| 3 | Letters by position; `letter:x`; P4 fixtures pass | fork `060a0b49` |
| 4 | `per-monitor-workspaces`; S10 passes | fork `e9c32712` |
| 5 | Grace, merge into one column, return home; S1–S9 pass | fork `ab14766c` |
| 6 | Pin, menu bar `*D3 F1📌`, F3 on every monitor | fork `bb54434f`, `169bc6f1` |
| 7 | Config, P6 key-plane check, install, live checks | mac_setup `b44d713` |
| 8 | `apps/Desk`; P3 replay and rule tests pass | mac_setup `40fbf98`, `1b11bd4` |
| 9 | Unit, recipe, launchd jobs, chord; live checks | mac_setup `213add3` |
| 10 | Script ready, waiting for you | mac_setup `f397113` |

The fork ends with 427 passing tests; `apps/Desk` has 9.

**Checked live on the desk, without touching cables:**

- `list-monitors`: 3996 is D, 39260 is F, the laptop is C. Every monitor started on its own
  floating 1, and nothing retiled.
- `workspace 3` lands on the focused monitor's 3; `workspace 39260-5` works; `workspace foo` is
  refused.
- The panel goes off 1.7 s after the agent starts. The keyboard light goes to 0 with auto off,
  and comes back to what it was (auto on, 0.48) when the panel does.
- `kill -9` of the agent: back in 0.12 s, no flicker.
- `mac desk toggle` holds the panel on past the settle time; `mac desk auto` hands back.
- Display sleep and wake: the panel stays off and the keyboard stays dark.
- Turning the panel on brings the laptop's three windows home from D's 1 within a second. Turning
  it off sends them back to D after exactly the 3 s grace. The homes survived an AeroSpace restart.
- Rebuilding Desk while it runs stops it cleanly with the panel on; `mac workspace up` reloads it.
- F3 opens one overlay per monitor and closes cleanly with hotkeys restored.
- The window layout was identical before and after two AeroSpace restarts.

**Where the build differs from the plan above:**

- The grace key is `unplugged-monitor-grace-seconds`, not `monitor-loss-grace`.
- No `%{workspace-local}`; nothing needed it.
- The stand-in display shows a throwaway `stand-in-1`, because AeroSpace must show something on
  every display. Windows born there move to the first real monitor at once, with no home.
- With per-monitor workspaces on, a monitor shows only its own workspaces. Commands naming a
  workspace no connected monitor owns are refused with a message. Old bare names (`3`) from
  before the switch move to the monitor they were shown on.
- The menu bar drops the `(F)` floating-mode badge, since `F` is now a monitor.
- Desk is a plain binary, not an app bundle, and `mac desk <verb>` is the only way you drive it.
  It holds a lock file to stay one agent, because the rescue job runs the same binary every 5 s.
- The agent's launchd job restarts it only after a crash. A clean stop turns the panel on first
  and stays stopped until `mac workspace up` reloads it, which is also how a rebuild takes effect.

**Not checked yet, and why:**

- **Pulling cables (H1, S2, S3, S6 on real hardware):** needs you. Step 3 of `e2e.zsh` unplugs
  both cables twice and times the panel.
- **The chord and F3 by key:** Karabiner's root daemon only starts on a `mac workspace up` that is
  given your password. I never enter passwords, so every `up` here skipped it.
- **Pressing the letters, the roll, and the pin double tap:** I don't send synthetic keystrokes.
  The same commands were run through the CLI.

One oddity seen once: the very first `workspace 3` right after `focus-monitor letter:f`, seconds
after the reboot under heavy load, left F on its 1. macOS finished focusing F's window late and
pulled focus back. It did not happen again in six tries at 0–300 ms gaps.
