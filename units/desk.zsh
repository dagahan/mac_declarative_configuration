requires=(base)

# The laptop panel is switched off, not blacked out, while a monitor is attached, and lights
# up again the moment none is left. The keyboard light goes out with it; the keys, Touch ID
# and the microphone keep working. ctrl+option+cmd+L overrides it until a cable changes.
build desk from=apps/Desk recipe=recipes/desk.zsh \
      artifact=.build/Desk.app \
      app=/Applications/Desk.app proc=Desk

# Both jobs live outside the directories launchd scans by itself, so nothing here starts
# at login: mac workspace up loads them, down turns the panel on and unloads them.
file desk-agent-plist from=config/launchd/desk.plist \
     at="$HOME/.config/mac_setup/launchd/com.mac-setup.desk.plist"

file desk-rescue-plist from=config/launchd/desk-rescue.plist \
     at="$HOME/.config/mac_setup/launchd/com.mac-setup.desk-rescue.plist"
