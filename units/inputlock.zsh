requires=(base)

# Right Shift + Delete holds every keyboard, mouse and trackpad event until
# pressed again. Karabiner holds the keys; this process holds the pointing
# devices, which anything that ends it gives back.
build inputlock from=apps/InputLock recipe=recipes/inputlock.zsh \
      artifact=.build/InputLock.app \
      app=/Applications/InputLock.app proc=InputLock

# Only the running agent can say whether its own grant is live, so it writes
# that down and this reads it.
manual inputlock-accessibility \
    do="System Settings > Privacy & Security > Accessibility: enable InputLock (it holds input with an event tap)" \
    detect='grep -qx "accessibility=true" "$STATE/inputlock/status"'

manual inputlock-input-monitoring \
    do="System Settings > Privacy & Security > Input Monitoring: enable InputLock (it holds the trackpad and mice while locked)" \
    detect='grep -qx "input_monitoring=true" "$STATE/inputlock/status"'
