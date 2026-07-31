requires=(base)

# The one plist that deliberately lives in ~/Library/LaunchAgents, the directory
# launchd scans by itself at login.
#
# The rule is that nothing starts at login. This starts nothing — it only ever
# turns things OFF, so it cannot leave the machine in a state you did not ask
# for, and it fails open: if it never runs you are exactly where you were.
#
# It exists because the persistent half of the workspace outlives the runtime
# half. Karabiner's cask registers its launchd jobs system-wide and enabled, so
# after a reboot the remapper is running while nothing it remaps to is: cmd+space
# becomes a launcher that is not there, cmd+w and cmd+q are swallowed by rules
# whose owner never started, and the Dock is hidden behind a 1000 second reveal
# delay. Every reboot landed on a machine with no working shortcuts until
# `mac workspace up` was typed — and typing it needs a terminal you cannot open.
#
# So: at login, hand the mac back. `mac workspace up` is then always a deliberate
# act, which is how it was asked for.
file workspace-down-plist from=config/launchd/workspace-down.plist \
     at="$HOME/Library/LaunchAgents/com.mac-setup.workspace-down.plist"
