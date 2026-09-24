# Multi-monitor desk — architecture

This file describes how the desk works for a MacBook kept open under two monitors. Each monitor
owns its own workspaces 1–0. Monitors are reached by keys that match where they sit. The laptop
panel powers off while monitors are attached, and comes back on by itself when they aren't.

Every fact this design relies on was measured in
[test_before_writing_architecture.md](test_before_writing_architecture.md). Section numbers there
are cited as A1–B7.

## 1. Decisions

**Approved by you:**

- A monitor is a physical device, identified by its serial number (B6). Its letter only says
  where it sits now.
- Letters come from the home row by position: `D` left, `F` right, `S D F` for three monitors. A
  monitor in a lower row gets `X C V`. The laptop under the monitors is `C`.
- `option` = go. `option+shift` = carry the window. Digits = the focused monitor's own 1–0.
  Keys combine as rolls, never as simultaneous chords.
- Pin: a double-tap, visible while it lasts, with no timer.
- Unplug: after a grace period, windows join the same-numbered workspace on the nearest monitor,
  stacked in one column. They remember home and go back on replug. Moving one by hand clears its
  home. A monitor the Mac has never seen starts empty.
- Desk mode shows **no indicator** on screen.
- There is no "places" abstraction: workspaces belong to physical monitors and nothing else.
- Close stays on `option+W`.

**Open. I chose a default for each; change any of them before implementation starts:**

| Question | Default in this design |
|---|---|
| Finder's key, since `option+shift+F` now carries a window to monitor F (A6) | `option+shift+E` |
| The desk-mode chord | `ctrl+option+cmd+L` (L for laptop) |
| What cmd-tab lists | Unchanged: the focused workspace, which is now the focused monitor's |
| "Displays have separate Spaces" | Unchanged: on |

## 2. The pieces

| Piece | Where | Owns |
|---|---|---|
| AeroSpace fork | `vendor/AeroSpace` (branch `mac-setup`) | Monitor identity and letters, per-monitor workspaces, unplug/replug, keys, F3, menu-bar text |
| Desk helper | `apps/Desk`, new, shaped like `apps/InputLock` | The laptop panel's power and the keyboard light. Nothing else. |
| mac_setup | `config/aerospace/aerospace.toml`, `config/karabiner/karabiner.json`, `units/`, `recipes/` | Declaring and starting all of the above, and handing the Mac back on `mac workspace down` and at login |

The helper and AeroSpace never talk to each other. The helper changes which displays exist;
AeroSpace reacts to the displays it sees. Either one keeps working if the other is dead.

## 3. Monitors

**Identity.** Every monitor carries a key:

- the laptop panel: `builtin`;
- an external: its serial (`3996` left, `39260` right).

Display ids are never used, because they swapped on replug (B6). The key is read from the
screen's `NSScreenNumber` through `CGDisplaySerialNumber` and `CGDisplayIsBuiltin`. It extends
`Monitor` / `MonitorImpl` in `Sources/AppBundle/model/Monitor.swift`.

**The stand-in display.** When no real display is left, macOS adds an invisible display (B6):

- serial 0;
- vendor code `unkn` (`0x756E6B6E`);
- model code `virt` (`0x76697274`);
- 1920×1080, and it becomes the main display.

Both AeroSpace and the helper treat it as **no monitor**. It has no letter and is never a merge
target. AeroSpace has to show some workspace on every display, so the stand-in gets a throwaway
`stand-in-1`. A window born there during that second moves to the first real monitor at once,
with no home to return to.

**Letters.** Letters are computed from the monitors' current frames every time the set of
monitors changes:

1. Group monitors into rows by vertical overlap. The top row comes first.
2. Order each row left to right.
3. Hand out letters by how many monitors the row holds:

| Row | 1 monitor | 2 | 3 | 4 |
|---|---|---|---|---|
| top | D | D F | S D F | S D F G |
| next | C | C V | X C V | X C V B |

On your desk this gives left `D`, right `F`, and the laptop `C` when it's on (A1). With the
laptop alone, it's the only monitor in the top row, so it's `D`.

Commands address monitors as `letter:d`, a new case in `MonitorDescription`
(`Sources/Common/model/MonitorDescription.swift`). A bare `d` already means "name matches
regex d", so it can't be reused.

## 4. Workspaces per monitor

- **Names.** Each monitor owns ten workspaces, named `<key>-<n>`: `3996-3`, `39260-1`,
  `builtin-7`. Commas and a few reserved words are the only forbidden names, so these are valid.
  You never type these names. You type `3`, and it's resolved against a monitor.
- **Config.** A new setting, `per-monitor-workspaces = ['1','2','3','4','5','6','7','8','9','0']`,
  turns the model on and names the local numbers. With it on, `persistent-workspaces` is empty;
  a known monitor's ten workspaces are always kept.
- **Owner.** A workspace's owner is the monitor whose key is in its name. While the owner is
  connected, the workspace is force-assigned to it (`forceAssignedMonitor`,
  `tree/WorkspaceEx.swift:54`), so it can never drift to another monitor.
- **Resolution.** In `workspace 3` and `move-node-to-workspace 3`, a bare local number resolves
  against a monitor:
  - `workspace 3` uses the **focused monitor**;
  - `move-node-to-workspace 3` uses the **window's monitor**, unless a pin is active (§7).

  Fully qualified names (`3996-3`) still work, for scripts and the CLI.
- **Floating 1.** `floating-workspaces = ['1']` is matched against the local number. Every
  monitor's 1 is floating. Four fork checks read that list today:
  - `MinimizeGuard.swift:54`
  - `BordersSync.swift:10`
  - `HotkeyBinding.swift:65`
  - `MissionControl.swift:147`

  All four switch from the global name to the local number.
- **Startup.** The workspace a monitor starts on is its own `1`, which is floating
  (`getStubWorkspace`, `tree/Workspace.swift:16`). Every monitor therefore starts on a floating
  workspace, and `mac workspace up` doesn't retile anything on any monitor. This fixes on every
  monitor the problem that `after-startup-command = ['workspace 1']` was written for.
- **Saved state.** `RestoreState` saves full names. A window's workspace survives an AeroSpace
  restart unchanged, because the names are stable.

## 5. Keys

All of these are native AeroSpace bindings, with no shell hop (A8). They are declared in both
`mode.main` and `mode.floating`. AeroSpace binds by physical key, so they behave the same in ABC
and Russian (A6).

| Keys | Does | Command |
|---|---|---|
| `option+S D F G` | Focus a top-row monitor | `focus-monitor letter:d` |
| `option+X C V B` | Focus a lower-row monitor (the laptop, when it's on beside the monitors) | `focus-monitor letter:c` |
| `option+1…0` | Workspace N of the focused monitor | `workspace 3` |
| `option+shift+letter` | Carry the window to that monitor's visible workspace; focus follows | `move-node-to-monitor --focus-follows-window letter:f` |
| `option+shift+1…0` | Send the window to workspace N of its monitor, or of the pinned monitor | `move-node-to-workspace 3` |
| double-tap `option+letter` | Pin that monitor | handled inside `focus-monitor` |
| `option+Esc` | Clear the pin | `pin-monitor off` |
| `option+W` | Close, unchanged | |
| `option+shift+E` | Finder (moved off `option+shift+F`) | `smart-open Finder` |
| `F3` | Overview on every monitor | Karabiner → `aerospace mission-control` |
| `ctrl+option+cmd+L` | Desk mode toggle | Karabiner → `mac desk toggle` |
| ~~`option+shift+Tab`~~ | Removed. AeroSpace refuses to move a monitor-owned workspace, and it contradicts per-monitor workspaces anyway | |

**Rolls.**

- Hold option, tap `F`, tap `3`: F's workspace 3.
- Hold option+shift, tap `F`, tap `7`: the window goes to F's 7, and you end up on F.
- A bare `option+3` is "3 here".

The cost of binding option: in Russian, `option+1…0` types `! @ # $ % ^ & * { }` (A6). Today's
config already blocks those, and this design changes nothing about it.

## 6. Unplugging and replugging

AeroSpace notices a change on its next refresh (`layout/refresh.swift:43` → `gcMonitors()`).
Today it only reacts when the **number** of monitors changes (`tree/Workspace.swift:136`). It
will react when the **set of monitor keys** changes.

1. **A monitor disappears.** Its key and last frame are noted, with a timestamp. Nothing moves
   yet, and its workspaces stay as they are, hidden.
2. **Grace period.** `unplugged-monitor-grace-seconds`, 3 by default. The measurements showed no blinks at
   all: the power button doesn't disconnect (B4), and sleeping monitors stay online (B5). The
   grace period exists for two reasons:
   - A reseated cable should cause nothing.
   - When the last monitor leaves, the helper takes about 1 s to light the panel (§8). Until
     then, the only display is the stand-in. Three seconds ensures windows land on the panel,
     never on the stand-in.

   If the same key returns within the grace period, nothing happened.
3. **Merge.** After the grace period, each workspace of the lost monitor that has windows moves
   into the same-numbered workspace of the **nearest real monitor**, measured from the lost
   monitor's last frame. Tiled windows go into **one accordion column** appended at the edge of
   that workspace, so the host's own layout keeps its sizes and the visitors are visibly one
   group. Floating windows keep their frames, clamped onto the new monitor by the existing
   `Floating frames` code. Each moved window gets `home = (key, n)`.
4. **Return.** When a monitor with a known key appears, every window whose home is that key goes
   back to its own workspace, in its saved order, and its home is cleared.
5. **Your move wins.** Any move by your hand clears the window's home: a key command, a drag, or
   F3. It then stays where you put it.
6. **New monitor.** A key never seen before gets ten empty workspaces and shows its own 1.
   Nothing is pulled onto it.

`home` is saved in `SavedWindow` (`persistence/RestoreState.swift:12`) as an optional field, so a
restart doesn't lose it. The monitor-change code in `rearrangeWorkspacesOnMonitors()`
(`tree/Workspace.swift:166`) maps old screens to new ones by key first, and only falls back to
nearest point for monitors it doesn't know.

**Walking away from the desk.**

1. You unplug both cables.
2. The helper lights the panel in about 1 s.
3. The laptop's own windows come home from `D`, where they were visiting.
4. Three seconds later, D's and F's windows join the laptop's workspaces by number.

Plugging back in reverses it. D and F take back their windows. The helper turns the panel off
after 1.5 s of stable monitors. The laptop's windows then join `D` by number, because D is
nearest to where the laptop sits.

## 7. Pin

- Double-tapping `option+D` within 300 ms pins monitor D.
- While D is pinned, `option+shift+1…0` sends the focused window, from any monitor, to D's
  workspace N. Focus stays where it is. This is for moving several windows onto one monitor.
- Focus keys behave normally while pinned.
- Double-tapping the same letter again, or `option+Esc`, clears the pin.
- It is visible in the menu bar while it lasts (§9).

## 8. Desk mode — the helper

**Shape.** Desk is one binary with two roles, the same shape as InputLock:

- **The agent**, `mac-desk agent`: an accessory `NSApplication`, one instance at a time.
- **Commands** sent to the agent over distributed notifications: `on`, `off`, `toggle`, `auto`,
  `status`, `rescue`.

If the agent isn't running, `on` and `rescue` do the work themselves, just as InputLock's CLI
releases the keyboard by itself. The safe direction never depends on the agent.

**Real monitors.** A display counts when it is:

- online (not "active", since sleeping monitors are inactive — B5);
- not built-in;
- not mirrored;
- serial ≠ 0;
- not the `unkn`/`virt` stand-in.

**The rule.** It's evaluated every 100 ms on its own dispatch queue, and also when
`NSApplication.didChangeScreenParametersNotification` fires. Polling is the part that's proven
(B, log row).

| Situation | Panel |
|---|---|
| No real monitors | **On, immediately.** Dark time ≈ 0.1 s poll + 0.85 s switch (B2). |
| At least one real monitor, stable 1.5 s, automatic | Off |
| You pressed the chord | Your choice holds until the set of real monitor serials changes; then it's automatic again |
| You press the chord to turn it off with no real monitors | Refused. The fail-open rule wins. |

**Switching.** Session scope only. App-only was measured not to heal itself when the process dies
(B1). The panel id is remembered while it's visible and saved to the state file, because a
disabled panel vanishes from every display list (B1).

**Keyboard light.**

- When the panel turns off: save the brightness and auto setting, then set auto off and
  brightness 0. That held through typing, sleep and unplugging (B3–B6).
- When the panel turns on: restore both.
- It is reasserted after wake while the panel is off.

**State.** `$XDG_STATE_HOME/mac_setup/desk/status` and `events.log`, written the way InputLock
writes its own. There is no on-screen indicator.

**Fail-open, in layers.** Nothing in macOS brings the panel back (B6, B7), so every layer is
ours:

| What failed | What brings a screen back | How fast |
|---|---|---|
| The last real monitor is unplugged | The agent's rule | About 1 s |
| The agent crashed | launchd `KeepAlive` with `ThrottleInterval` 1 restarts it, and its first evaluation lights the panel | About 1–2 s |
| The agent hung | A separate launchd job runs `mac-desk rescue` every 5 s: panel off and no real monitors → on | Up to about 6 s |
| Both launchd jobs are gone | The Karabiner chord runs `mac desk on` directly, with no agent needed | Instant |
| Karabiner is gone too | Plug any monitor in (proven in B6) | — |
| Logout or reboot | The existing login agent runs `mac workspace down`, and down runs `mac desk on` | At login |
| `mac workspace down` | Its revert runs `mac desk on` before stopping anything | — |

Reopening the lid is **not** a layer: it was measured not to help (B7).

**Permissions.** None. The display and keyboard calls needed no privacy grant when run from a
plain shell (A2, B1–B3). The hotkey belongs to Karabiner.

## 9. F3 and the menu bar

**F3.**

- `MissionControl.show()` (`ui/MissionControl.swift:61`) opens one panel per real monitor, each
  on its own screen. Each panel shows that monitor's letter and its own 5×2 grid of workspaces.
- Arrow keys move within the focused monitor's panel.
- Clicking a tile on any panel switches **that** monitor.
- All panels close together, and hotkeys are suspended once for all of them.
- Only connected monitors appear, as you asked.

**Menu bar.** The existing workspace text (`ui/TrayMenuModel.swift`) becomes one entry per monitor
in letter order, like `*D3 F1📌`: `*` marks the focused monitor and `📌` the pinned one. This
replaces the text that's there today and adds no new indicator. The old `(F)` badge for the
floating binding mode is dropped, because `F` is now a monitor.

## 10. How it sits in mac_setup

- **`units/desk.zsh`** (new):
  - `build desk from=apps/Desk recipe=recipes/desk.zsh`, installed as the plain binary `~/.local/libexec/mac-desk`, driven only through `mac desk <verb>`;
  - two plists as `file` resources under `~/.config/mac_setup/launchd/`: the agent (KeepAlive)
    and the rescue job (StartInterval 5).

  These live outside the directories launchd scans at login, the same rule the VPN tree
  follows.
- **`units/activate.zsh`** gains
  `run desk check='zsh recipes/desk.zsh check' apply='zsh recipes/desk.zsh up' revert='zsh recipes/desk.zsh down'`.
  It's a `run` resource, not a `daemon`, because `mac workspace down` skips `daemon` resources
  (`engine/cmd.zsh:592`), and down must reach this one.
  - `up` loads both jobs.
  - `down` runs `mac desk on`, then unloads both.
- **`config/karabiner/karabiner.json`** gains one rule: `ctrl+option+cmd+L` → `mac desk toggle`.
- **`config/aerospace/aerospace.toml`**:
  - the key table in §5, in both modes;
  - `per-monitor-workspaces`;
  - `unplugged-monitor-grace-seconds = 3`;
  - `floating-workspaces = ['1']`;
  - `persistent-workspaces = []`.
- **The login agent** that already runs `mac workspace down` at login is unchanged. It now also
  guarantees the panel is on after every login.

## 11. Deliberately left out

- **Any desk-mode indicator.** You rejected it.
- **A separate on-screen focus strip.** The menu-bar text covers "which workspace where".
- **Changes to AltTab.** It reads the focused workspace name, and the new names contain no
  whitespace, so its `<isFloating> <workspace>` nudge line still parses.
- **Changing "Displays have separate Spaces", type-ahead in F3, learned app homes, head-pose.**
  These are future ideas, not part of this build.

## 12. Known risks

- **Private display call.** A macOS update could remove `SLSConfigureDisplayEnabled`. The helper
  checks for it at start; if it's missing, the helper never turns the panel off. The Mac stays a
  plain laptop.
- **Surviving logout or reboot.** Whether a disabled panel stays disabled across logout or reboot
  hasn't been measured. The login agent covers it either way.
  [test_before_implementation.md](test_before_implementation.md) measures it if you want the
  answer.
- **Whether the stand-in display leaves once the panel is lit** hasn't been observed, because in
  B6 the panel never came on. It doesn't matter to the rule, but the merge ignores the stand-in
  either way.
- **One AeroSpace refresh sees three changes at once when you undock:** the stand-in appearing,
  the panel returning, and the monitors leaving. The grace period and key-based mapping exist for
  exactly this. The attended end-to-end test at the end exercises it on the real desk.
