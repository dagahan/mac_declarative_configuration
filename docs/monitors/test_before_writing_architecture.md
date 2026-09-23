# Tests before writing the architecture

The architecture depends on facts about this Mac that nobody has measured yet. Each test below
answers one question the architecture can't be written without. Nothing here changes how the repo
or the desktop behaves. The probes live in [probes/](probes/), and every result is recorded at the
end of this file.

## What is already decided

These are inputs to the tests. The tests don't reopen them.

- **A monitor is a physical device, identified by its serial number.** A monitor's letter only
  says where it sits right now.
- **Monitor keys are on the home row, left to right:** `D` `F`, or `S` `D` `F` for three
  monitors. A monitor in a lower row takes the row below: `C` `V`. The laptop panel under the
  monitors is `C`.
- **`option` means go, `option+shift` means carry the window.** A digit is that monitor's own
  workspace. Rolls: hold option and tap `D` then `3`. A bare `option+3` means the focused
  monitor's 3.
- **Pin:** an explicit double-tap that stays visible until escape. There is no timed latch.
- **Unplugging a monitor:**
  1. A short grace period during which nothing moves.
  2. Then its windows join the same-numbered workspace on the nearest remaining monitor, stacked
     in one column there.
  3. Each moved window remembers its home and goes back when that monitor returns.
  4. Moving a visiting window by hand clears its home.
  5. A monitor the Mac has never seen starts empty.
- **Desk mode:** the laptop's resting state is a normal laptop. There is no on-screen indicator
  of the mode.
- **F3** shows only connected monitors.
- **Close stays on `option+W`.**

## How the tests run

- **Part A: headless.** Nothing on screen changes and no input is sent. It runs unattended.
- **Part B: one attended session, about 5 minutes.** You need to be at the desk with the lid
  open and the charger connected. You run one command:
  ```bash
  ~/mac_setup/docs/monitors/probes/session.zsh
  ```
  It asks you to do the physical parts: touch the sensor, press a monitor's power button, unplug
  cables, close the lid. A logger records every display event with timestamps. A separate
  watchdog process turns the laptop panel back on if anything goes wrong. The results go to
  `~/.local/state/mac_setup/monitors/<time>/`.

## Part A — headless

| # | Question | Why the architecture needs it | Method | Passes when |
|---|---|---|---|---|
| A1 | Can each monitor be told apart by serial number, and do the letter rules give `D` `F` `C` on this desk? | Serial is the planned identity for a monitor | `probe displays`: CoreGraphics id, serial, vendor, model, built-in flag, frame, main, plus the computed letters | All serials non-zero and distinct; left `D`, right `F`, laptop `C` |
| A2 | Do the private display and keyboard-light calls exist on macOS 26.2? | Without them desk mode can't be built | `probe api`: symbol lookup only, nothing called | `SLSConfigureDisplayEnabled` and `KeyboardBrightnessClient` present |
| A3 | Can the keyboard light be read without side effects? | Decides whether the helper can save and restore the light | `probe kbd get`: ids, level, auto-brightness, idle dim, suppressed | Built-in keyboard found; values read |
| A4 | Is Touch ID available with the lid open? | Baseline for B3 | `probe touchid can`: availability check, no prompt | Available |
| A5 | Does the built-in microphone show up as an input? | Baseline for B3 | `probe mic`: CoreAudio device list | "MacBook Pro Microphone" alive, with input |
| A6 | Which characters do the candidate chords type in ABC and Russian, and do they collide with any existing binding? | Picks the final key map | `probe keys` (translates each key with the layouts themselves) plus a scan of `aerospace.toml`, `karabiner.json` and the system shortcuts | Every candidate chord is free, or has a named replacement |
| A7 | Where does the fork already handle monitor identity, monitor changes, saved window state and tests? | The architecture must extend existing code, not add a parallel system | Read the fork's code | Each planned piece has a named hook |
| A8 | How slow is a shell hop compared with a native binding? | Decides whether the hot path must be native | Reuse the numbers already measured in `aerospace.toml` and AltTab; no new run | Numbers found |
| A9 | Can the Mac's existing logs show past monitor blinks? | If yes, B4 and B5 could be skipped | Search the power log and WindowServer log | Connect/disconnect events with times |
| A10 | Do the probes themselves run correctly end to end? | A broken test session wastes your 5 minutes | Run `session.zsh --dry-run` on a pty: every hardware call becomes a no-op and the answers are scripted | Every step runs and the summary prints |

## Part B — attended session

| # | Question | Why the architecture needs it | Method | Passes when |
|---|---|---|---|---|
| B1 | Does the "app-only" display setting truly darken the panel, and does the panel come back by itself when the process holding the setting is killed? | If yes, the helper *is* the fail-open mechanism: a dead helper means a lit panel with no watchdog logic needed | A holder process turns the panel off with app-only scope. You say whether it's fully dark. The holder is killed with SIGKILL, and the logger times the panel's return. The watchdog steps in after 3 s if it doesn't return | You confirm it's dark; the panel returns without the watchdog |
| B2 | Does the "session" setting turn the panel off and back on reliably? | This is the fallback path if B1 fails | Turn it off with session scope, then on again explicitly; time both | Off and back on, each within 2 s |
| B3 | With the panel off, do Touch ID, the microphone and the laptop keys work, and does the keyboard light stay at 0? | These are the reasons the lid stays open | Touch ID prompt that you answer with a touch; 2 s microphone level; you type `desk` on the laptop keyboard; the light is set to 0 with auto off, and you say whether it stayed off | Touch passes; mic level above silence; `desk` received; light stays 0 |
| B4 | When a monitor's power button is pressed, does macOS see the monitor disconnect? For how long? Does it come back with the same identity? | Sets the grace period and shows what an ordinary action looks like to the system | You turn the right monitor off and on; the logger records it | Serial and position unchanged after; blink duration measured |
| B5 | During display sleep, do the monitors disconnect? Does the panel come back on wake? Does Touch ID unlock with the panel off? | Decides whether sleep must be ignored as a topology change | `pmset displaysleepnow`; you wake with the mouse and unlock | Measured either way; the panel stays off unless the monitors truly left |
| B6 | With both cables pulled while the panel is off, does macOS turn the panel back on by itself? How fast does the watchdog? On replug, do identity, arrangement and the main display come back? | This is the worst case for fail-open, and the unplug design rests on identity surviving | You unplug both and replug both; the logger records it; the watchdog waits 3 s before acting | Panel lit within 3 s; same serials and positions after replug |
| B7 | Is closing and reopening the lid a physical way to get the panel back? | A last-resort escape that needs no software | Panel off; you close the lid for 3 s and reopen it | Measured either way |

### Safety net during Part B

- A watchdog process that is separate from the session turns the panel back on if any of these
  happens:
  - no monitor has been connected for 3 s;
  - the process holding the panel off died and the panel didn't return within 3 s;
  - the session stopped responding for 10 s;
  - the panel has been off for 10 minutes.
- On exit, including ctrl+c, the session turns the panel on, restores the keyboard light, and
  stops every helper.
- Nothing uses the permanent display setting.
- If every screen goes dark: close the lid, wait 3 s, open it. If it's still dark, press ctrl+c
  in the session window.
- macOS moves windows off the laptop panel when the panel turns off, and they may not come back
  when it turns on again.

## What each outcome changes

| Result | Consequence for the architecture |
|---|---|
| B1: dark, and the panel returns when the holder dies | The desk-mode helper holds the panel off with app-only scope. A crash or kill gives the panel back by itself. The watchdog only has to cover "no monitors left". |
| B1: dark, but the panel stays off after the holder dies | Session scope plus an independent watchdog. Recovery depends on the watchdog, so its liveness becomes part of `mac workspace up` / `down`. |
| B1: not fully dark | Desk mode as specified can't be delivered. Stop there and decide whether a dark-but-lit panel is acceptable. |
| B3: Touch ID or mic fail with the panel off | Desk mode keeps the panel on at minimum brightness instead, or is dropped. |
| B3: keyboard light comes back | The helper must reassert the light on the "suppressed" and "dimmed" notifications, not set it once. |
| B4/B5: monitors disconnect on a button press or sleep | The grace period is set from the measured blink, and topology changes during display sleep are ignored until wake. |
| B6: macOS doesn't restore the panel | The watchdog is the only protection. It must not depend on AeroSpace, and it runs as its own process. |
| B6: serials change on replug | Monitor identity falls back to vendor+model+port, and "remember home" keys on that instead. |
| B7: lid reopen restores the panel | It is documented as the physical escape. |

## Results

### Part A — run 2026-09-23, lid open, desktop down (AeroSpace and Karabiner not running)

| # | Result |
|---|---|
| A1 | **Pass.** Left monitor: serial 3996, id 3, 144 Hz. Right monitor: serial 39260, id 2, 72 Hz. Laptop panel: serial 4251086178, id 1, built-in. All three serials are distinct. Both monitors share vendor 16652 and model 50223, so only the serial tells them apart. The letter rule gives left `D`, right `F`, laptop `C`. The monitors sit above the laptop (y = −1440). The **laptop panel is currently the main display**, the one with the menu bar. |
| A2 | **Pass.** `SLSConfigureDisplayEnabled`, `CGSConfigureDisplayEnabled` and `KeyboardBrightnessClient` are all present. |
| A3 | **Pass.** One built-in keyboard (id 95158272): brightness 0.69, auto-brightness on, idle dim 0, not suppressed. Reading it changes nothing. |
| A4 | **Pass.** Touch ID is available (biometry type 1). |
| A5 | **Pass.** "MacBook Pro Microphone" is alive, built-in, with input. |
| A6 | **One collision, and one cost you already pay.** The collision: `option+shift+F` opens Finder today (`aerospace.toml:146`), so Finder needs another key. The system's only option shortcut is ctrl+option+space (next input source); Karabiner has no option rules. The cost: in the **Russian layout, `option+1…0` types `! @ # $ % ^ & * { }`**. Today's `option+1…0` bindings already block that, and the plan changes nothing about it. On letters, the plan's chords only block rare symbols (ABC: ∂ ƒ ß ç √; Russian: ћ ÷ ы ≠ µ). `option+E` is a dead key (´) in ABC. Full table below. |
| A7 | **Every piece has a hook in the fork.** Listed below. |
| A8 | **Decided from existing numbers.** A CLI call takes about 70 ms, and 250–300 ms right after a workspace switch (`aerospace.toml`, the `exec-on-workspace-change` comment; `alt-tab-macos/src/switcher/state/Windows.swift:571`). Every hot-path key has to be a native AeroSpace command, never a shell hop. |
| A9 | **Not usable.** The power log records only "Display is turned on/off" (82 entries), and searching the WindowServer log over 6 hours found no connect or disconnect lines. Blinks have to be measured live, so B4 and B5 stay. |
| A10 | **Pass.** A dry run on a pty answered all 12 prompts, exited 0, and left no helper process running. The logger, the watchdog (in dry mode) and every step marker were written. A synthetic event stream exercised every analyzer branch: panel off and back by itself, back by the watchdog, a monitor blink, sleep drops, replug with new ids, and the lid. Each probe call takes under 1 s. |

**Key plane (A6):** what each chord types when nothing binds it.

| key | ABC ⌥ | ABC ⌥⇧ | RU | RU ⌥ | RU ⌥⇧ |
|---|---|---|---|---|---|
| 1 2 3 4 5 | ¡ ™ £ ¢ ∞ | ⁄ € ‹ › ﬁ | 1 2 3 4 5 | ! @ # $ % | \| " £ € ∞ |
| 6 7 8 9 0 | § ¶ • ª º | ﬂ ‡ ° · ‚ | 6 7 8 9 0 | ^ & * { } | ¬ ¶ √ ' ` |
| s d f | ß ∂ ƒ | Í Î Ï | ы в а | ы ћ ÷ | Ы Ћ ÷ |
| x c v | ≈ ç √ | ˛ Ç ◊ | ч с м | ≈ ≠ µ | ≈ ≠ µ |
| w | ∑ | „ | ц | џ | Џ |

**Fork hooks (A7):**

| Need | Existing code |
|---|---|
| Monitor identity | `Sources/AppBundle/model/Monitor.swift:60-115`. Monitors are built from `NSScreen`, keyed by their top-left point, and sorted by x then y (`:113`). There is no serial yet; the screen's display id is already reachable through `NSScreenNumber`. |
| Reacting to monitor changes | `layout/refresh.swift:43` calls `gcMonitors()` on every refresh. `tree/Workspace.swift:136` only rearranges when the **number** of monitors changes. `rearrangeWorkspacesOnMonitors()` (`:166`) maps old screens to new ones by nearest point. This is where grace, merge and return go. |
| Workspace ↔ monitor | `tree/WorkspaceEx.swift:54` `forceAssignedMonitor`; the fallback chain is at `tree/Workspace.swift:108`. |
| Saved window state | `persistence/RestoreState.swift:12` `SavedWindow` stores workspace, floating, order, weight and frame. The home monitor becomes one more field. |
| F3 overview | `ui/MissionControl.swift:61` draws one panel on `NSScreen.main`. |
| Key handling | `config/HotkeyBinding.swift:32` registers by key code through the HotKey library, so bindings are layout-independent. The floating-mode switch is at `:65`. |
| Tests | Unit tests run against one fixed test monitor (`Monitor.swift:98`, `:108`). Multi-monitor tests will need that test double extended. |

### Part B — run 2026-09-23 17:23, `~/.local/state/mac_setup/monitors/20260923-172345/`

Times are seconds from the start of the session log.

| # | Result |
|---|---|
| B1 | **The panel goes truly dark; app-only is not self-healing.** It was off 0.9 s after the call, and you confirmed no picture and no glow. A disabled panel disappears from the display list entirely, and the right monitor became the main display. After the holder was killed with SIGKILL, the panel **did not come back**; the watchdog turned it on 3.4 s later. App-only therefore buys nothing over session scope. |
| B2 | **Session scope works both ways.** Off in 0.85 s, on in 0.82 s. When the panel comes back it returns to its remembered position **and becomes the main display again** (the menu bar moves back to the laptop). |
| B3 | **Everything the lid stays open for still works with the panel off.** The laptop keys worked (you typed "gsffdsfdsjfsd hello"). The keyboard light held at 0 with auto-brightness off, you confirmed it stayed off, and it stayed at 0 through B4, B5 and B6. The microphone was live: mean −60 dB, peak −48 dB, which is room noise, not the digital silence of a cut-off mic. No speech was captured, though, so this is weak evidence. The in-app Touch ID prompt ended with "user chose password" (−3), which is inconclusive. But you unlocked the **lock screen with your fingerprint** in B5 with the panel off, which settles it. |
| B4 | **A monitor's power button doesn't disconnect it.** No display event at all while the right monitor was off. Pressing the button produces no blink to absorb. |
| B5 | **Sleeping monitors stay connected.** During display sleep both monitors reported *online, inactive, asleep*; they were not removed. They were awake again 2.9 s later, and the panel stayed off. "Active" is therefore the wrong test for "a monitor is present"; "online" is right. Fingerprint unlock worked. |
| B6 | **FAILED — you were left with no screen.** Unplugging the left monitor (222.5 s) and then the right (226.6 s) did not leave zero displays. macOS created an invisible virtual display (id 18, serial 0, vendor code `unkn`, model code `virt`, 1920×1080) and made it the main display. **macOS did not turn the panel back on**, and the watchdog counted the virtual display as a monitor, so it never acted. You were in the dark for 21 s, until you plugged the left monitor back in (247.7 s). You unplugged it again (258.9 s, a new virtual display, id 19) and replugged it (266.1 s), for another 7 s of darkness. Both monitors were back at 274 s. After replugging, the **display ids swapped** (left 3→2, right 2→3), but the serials were unchanged, and once the panel returned macOS restored the exact original arrangement. |
| B7 | **Reopening the lid is not an escape.** With the panel off and the monitors connected, the lid closed (292.8 s) and opened (296.5 s), and the panel stayed off; you confirmed it. The cleanup turned it on at 305.5 s. |
| log | The display-change callback never fired in the command-line logger (0 events). Polling every 100 ms caught every change. |

**What went wrong on my side, and what's fixed.** The safety net relied on two false assumptions:
- that "no monitors" means zero displays; macOS substitutes a virtual one;
- that reopening the lid brings the panel back; it doesn't.

The watchdog now counts only real monitors (online, not built-in, not mirrored, serial ≠ 0, and not the `unkn`/`virt` fallback), and it acts immediately with no grace period. The session's safety text now says to plug a monitor back in. The logger stops itself on exit: in this run it outlived the session, because the cleanup matched the `swift` launcher but not the interpreter underneath it. Both are fixed in `probes/`.

### Facts the architecture is built on

1. The panel can be powered fully off with the lid open. Only session scope is useful; toggling takes about 0.85 s each way.
2. **Nothing but us turns the panel back on.** Not macOS, not the lid, not the app-only scope. Fail-open is entirely our job, and "no monitors" must be detected as *no real monitors*, because macOS fills the gap with an invisible `unkn`/`virt` display.
3. A monitor is present while it's *online*. Sleeping monitors are online but inactive. The power button causes no disconnect.
4. Identify monitors by **serial**. Display ids change on replug; serials and macOS's remembered arrangement don't.
5. Turning the panel on makes it the main display again and puts it back in its remembered position. Turning it off hands "main" to a monitor.
6. Touch ID (lock screen), the laptop keys and the keyboard light at 0 all work with the panel off. The microphone is live but untested with speech.
7. The helper has to poll, or run as a real app event loop. A command-line process got no display-change callbacks.
