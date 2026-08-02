requires=()
workspace=1

# Key repeat only takes full effect after a re-login; macOS offers no way to
# apply it live, so there is nothing to restart here.
default NSGlobalDomain KeyRepeat        int 2   on_workspace_down=delete
default NSGlobalDomain InitialKeyRepeat int 15  on_workspace_down=delete

# The three-finger swipe and the Mission Control gesture are off because AeroSpace
# owns those motions. With AeroSpace down they should answer again.
default com.apple.AppleMultitouchTrackpad                  TrackpadThreeFingerVertSwipeGesture int 0    on_workspace_down=2
default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture int 0    on_workspace_down=2
default com.apple.dock showMissionControlGestureEnabled    bool false                                   on_workspace_down=true
