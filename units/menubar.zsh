requires=(brew alttab)

stop AltTab      before='default:com.lwouis.alt-tab-macos/*'
stop Hammerspoon before='default:org.hammerspoon.Hammerspoon/*'

# AltTab stores booleans as literal strings; a -bool write is discarded on launch.
# These apps are all stopped by `mac workspace down`, so their own preferences only
# need to stop hiding the menu-bar icons that say the app is running.
default com.lwouis.alt-tab-macos menubarIconShown   string false  on_workspace_down=true
default com.lwouis.alt-tab-macos startAtLogin       string false  on_workspace_down=false
# ShowHowPreference raw index: 1 = hide (windowless ghosts otherwise show everywhere)
default com.lwouis.alt-tab-macos showWindowlessApps string 1      on_workspace_down=delete
# Upstream default is 100ms of dead time before the switcher is even built. Only an
# exact 0 takes the synchronous show path (App.swift showUiOrCycleSelection).
default com.lwouis.alt-tab-macos windowDisplayDelay string 0      on_workspace_down=delete
default org.hammerspoon.Hammerspoon MJShowMenuIconKey bool false  on_workspace_down=true

manual ayugram-menubar-icon \
    do="AyuGram > Settings > Advanced > uncheck 'Show icon in the menu bar' — then: mac ack ayugram-menubar-icon"
