requires=(brew alttab)

stop AltTab      before='default:com.lwouis.alt-tab-macos/*'
stop LinearMouse before='default:com.lujjjh.LinearMouse/*'
stop Hammerspoon before='default:org.hammerspoon.Hammerspoon/*'

# AltTab stores booleans as literal strings; a -bool write is discarded on launch.
default com.lwouis.alt-tab-macos menubarIconShown   string false
default com.lwouis.alt-tab-macos startAtLogin       string false
# ShowHowPreference raw index: 1 = hide (windowless ghosts otherwise show everywhere)
default com.lwouis.alt-tab-macos showWindowlessApps string 1
# LinearMouse JSON-encodes this enum: the value must contain literal quote bytes.
default com.lujjjh.LinearMouse   menuBarVisibilityMode string '"never"'
default org.hammerspoon.Hammerspoon MJShowMenuIconKey bool false

manual ayugram-menubar-icon \
    do="AyuGram > Settings > Advanced > uncheck 'Show icon in the menu bar' — then: mac ack ayugram-menubar-icon"
