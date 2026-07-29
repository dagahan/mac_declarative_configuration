requires=(base brew)

build ainto from=vendor/ainto-app recipe=recipes/ainto.zsh \
      artifact=AintoApp/build/Build/Products/Release/Ainto.app \
      app=/Applications/Ainto.app proc=Ainto

# Ainto keeps its hotkey in UserDefaults and flushes them on quit, so it has to
# be down while this is written. Karabiner maps Cmd+Space to it.
stop Ainto before='default:app.ainto.macos/*'
default app.ainto.macos globalHotkey string "⌘ ⇧ Space" on_workspace_down=delete

run spotlight-hotkey why="keep Spotlight's own Cmd+Space enabled — Karabiner intercepts it first" \
    check='zsh recipes/spotlight-hotkey.zsh check' \
    apply='zsh recipes/spotlight-hotkey.zsh apply'
