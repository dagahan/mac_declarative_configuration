requires=()

# Key repeat only takes full effect after a re-login; macOS offers no way to
# apply it live, so there is nothing to restart here.
default NSGlobalDomain KeyRepeat        int 2
default NSGlobalDomain InitialKeyRepeat int 15

default com.apple.AppleMultitouchTrackpad                  TrackpadThreeFingerVertSwipeGesture int 0
default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture int 0
default com.apple.dock showMissionControlGestureEnabled    bool false
