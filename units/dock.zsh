requires=()

# on_workspace_down= is the state `mac workspace down` leaves behind: a Dock you
# can actually reach. autohide-delay is the one that matters — 1000 seconds means
# the Dock never appears no matter where the cursor goes, which with the launcher
# hotkeys also down leaves no way to start anything.
# `delete` hands the key back to macOS instead of naming a value.
default com.apple.dock autohide                  bool   true      on_workspace_down=false
default com.apple.dock autohide-delay            float  1000      on_workspace_down=delete
default com.apple.dock autohide-time-modifier    float  0.3       on_workspace_down=delete
default com.apple.dock show-recents              bool   false     on_workspace_down=true
default com.apple.dock persistent-apps           array            on_workspace_down=delete
default com.apple.dock persistent-others         array            on_workspace_down=delete
default com.apple.dock launchanim                bool   false     on_workspace_down=true
default com.apple.dock mineffect                 string scale     on_workspace_down=genie
default com.apple.dock expose-animation-duration float  0         on_workspace_down=delete
default com.apple.dock no-bouncing               bool   true      on_workspace_down=false
