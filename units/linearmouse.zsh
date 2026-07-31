requires=(brew)

# Deliberately outside the workspace. Pointer behaviour is not part of the
# window-manager session: it should be there the moment you log in and it should
# never be stopped or started by `mac workspace up` / `down`, which is why this
# unit is not in WORKSPACE_SELECTORS and carries its own login agent.
#
# The second plist in ~/Library/LaunchAgents, and the only one that starts
# something. That is a deliberate exception, asked for: a mouse that stops
# working is not a fail-open outcome the way a stopped window manager is.
file linearmouse-plist from=config/launchd/linearmouse.plist \
     at="$HOME/Library/LaunchAgents/com.mac-setup.linearmouse.plist"

# LinearMouse JSON-encodes this enum: the value must contain literal quote bytes.
# No on_workspace_down= — `mac lint` requires one for every default, and the
# absence here would be a bug, so it declares the value it already has: this
# setting is never toggled by the workspace.
default com.lujjjh.LinearMouse menuBarVisibilityMode string '"never"' on_workspace_down='"never"'
