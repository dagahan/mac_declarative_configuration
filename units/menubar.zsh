requires=(software alttab)
workspace=1

# AltTab stores booleans as literal strings; a -bool write is discarded on launch.
# These apps are all stopped by `mac workspace down`, so their own preferences only
# need to stop hiding the menu-bar icons that say the app is running.
#
# stop_app= because both flush their preferences on quit: a write made while they
# are running is thrown away the moment they exit.
default com.lwouis.alt-tab-macos menubarIconShown   string false  on_workspace_down=true   stop_app=AltTab
default com.lwouis.alt-tab-macos startAtLogin       string false  on_workspace_down=false  stop_app=AltTab
# ShowHowPreference raw index: 1 = hide (windowless ghosts otherwise show everywhere)
default com.lwouis.alt-tab-macos showWindowlessApps string 1      on_workspace_down=delete stop_app=AltTab
# Upstream default is 100ms of dead time before the switcher is even built. Only an
# exact 0 takes the synchronous show path (App.swift showUiOrCycleSelection).
default com.lwouis.alt-tab-macos windowDisplayDelay string 0      on_workspace_down=delete stop_app=AltTab
default org.hammerspoon.Hammerspoon MJShowMenuIconKey bool false  on_workspace_down=true   stop_app=Hammerspoon

manual ayugram-menubar-icon \
    do="AyuGram > Settings > Advanced > uncheck 'Show icon in the menu bar'"
