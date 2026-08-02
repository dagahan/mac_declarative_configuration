requires=()
workspace=1

# on_workspace_down= is the state `mac workspace down` leaves behind: a Dock you
# can actually reach. `delete` hands the key back to macOS instead of naming one.
#
# The Dock stays auto-hidden in both modes — the difference is whether it can be
# summoned. Up: 1000s of delay, so the pointer never brings it back and it stays
# out of the way of a tiled desktop. Down: 0, so it appears the instant the
# pointer touches the bottom edge, which is the only launcher left once the
# hotkeys are off.
default com.apple.dock autohide                  bool   true      on_workspace_down=true
default com.apple.dock autohide-delay            float  1000      on_workspace_down=0
default com.apple.dock autohide-time-modifier    float  0.3       on_workspace_down=0.15
default com.apple.dock show-recents              bool   false     on_workspace_down=true
default com.apple.dock persistent-apps           array            on_workspace_down=delete
default com.apple.dock persistent-others         array            on_workspace_down=delete
default com.apple.dock launchanim                bool   false     on_workspace_down=true
default com.apple.dock mineffect                 string scale     on_workspace_down=genie
default com.apple.dock expose-animation-duration float  0         on_workspace_down=delete
default com.apple.dock no-bouncing               bool   true      on_workspace_down=false
