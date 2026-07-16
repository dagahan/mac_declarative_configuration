# mac_setup

Declarative setup for my macOS desktop: a Hyprland-style tiling workflow built on
[AeroSpace](https://github.com/nikitabobko/AeroSpace), a minimal Dock, and system
key remaps. One command reproduces the whole environment on a fresh Mac.

## Layout

```
install.sh              entry point — runs modules in order; `./install.sh 40` runs one
Brewfile                everything installed via Homebrew
modules/
  lib.sh                shared helpers (logging, safe symlinking with backups)
  10-brew.sh            Homebrew + Brewfile
  20-dotfiles.sh        symlinks config/* to live locations
  30-aerospace.sh       activates AeroSpace with the repo config
  40-dock.sh            Dock: autohide (0s delay / 0.3s slide), no pins, no recents
  50-keyboard.sh        Karabiner: Cmd+Tab disabled (vk_none)
config/                 single source of truth — edit here, effect is immediate
  aerospace/aerospace.toml
  kitty/kitty.conf
  karabiner/karabiner.json
vendor/
  AeroSpace/            upstream source as a submodule — the future fork
```

## Bootstrap on a fresh Mac

```sh
xcode-select --install
git clone --recursive <this-repo-url> ~/mac_setup
cd ~/mac_setup && ./install.sh
```

## Manual post-install steps (macOS demands a human)

1. **AeroSpace**: grant Accessibility when prompted
   (System Settings → Privacy & Security → Accessibility).
2. **Karabiner-Elements**: approve the driver extension in Privacy & Security,
   then enable `karabiner_grabber` / `karabiner_observer` under Input Monitoring.

## Working on the AeroSpace fork

`vendor/AeroSpace` tracks upstream today. To spin off:

1. Fork `nikitabobko/AeroSpace` on your git host.
2. Repoint the submodule: `git submodule set-url vendor/AeroSpace <fork-url>`.
3. Hack, then build with `cd vendor/AeroSpace && ./build-release.sh` (needs full Xcode).
4. Install the built .app and drop the `aerospace` cask from the Brewfile.

## Notes

- Modules are idempotent — rerun `./install.sh` any time; existing real files are
  backed up as `<name>.pre-mac_setup` before being replaced by symlinks.
- Karabiner's GUI writes to `karabiner.json` too; since it is a symlink, GUI edits
  land in the repo — review `git diff` after using the GUI.
- The Dock module wipes pinned apps by design. A pre-mac_setup Dock backup lives at
  `~/dock-backup-2026-07-16.plist` (restore: `defaults import com.apple.dock <file> && killall Dock`).
