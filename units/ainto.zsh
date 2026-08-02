requires=(base software)

build ainto from=vendor/ainto-app recipe=recipes/ainto.zsh \
      artifact=AintoApp/build/Build/Products/Release/Ainto.app \
      app=/Applications/Ainto.app proc=Ainto

# Ainto keeps its hotkey in UserDefaults and flushes it on quit, so it has to be
# down while this is written. Karabiner maps Cmd+Space to it. workspace=1 puts
# just this key in the desktop's hands — the build above is sync's job, not the
# workspace's.
default app.ainto.macos globalHotkey string "⌘ ⇧ Space" \
        on_workspace_down=delete stop_app=Ainto workspace=1

run spotlight-hotkey why="keep Spotlight's own Cmd+Space enabled — Karabiner intercepts it first" \
    check='zsh recipes/spotlight-hotkey.zsh check' \
    apply='zsh recipes/spotlight-hotkey.zsh apply' \
    irreversible="Spotlight's hotkey is a stock macOS default; turning it back off would only recreate the bug this fixes"
