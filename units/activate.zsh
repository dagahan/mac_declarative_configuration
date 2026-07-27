requires=(aerospace alttab ainto karabiner dock input menubar bitwarden dotfiles)

service Dock        kind=killall
service AltTab
service LinearMouse
service Hammerspoon path=/Applications/Hammerspoon.app
service Ainto
service Easydict
# No Karabiner-Menu service: karabiner.json hides its icon, so it quits on its
# own the moment it starts. The stop in the dotfiles unit is all that is needed.

run borders why="focused-window outline daemon (JankyBorders)" \
    check='pgrep -qx borders' \
    apply='zsh recipes/borders.zsh'

# Liveness first, restart second. Checking only for a pending restart meant a
# dead AeroSpace looked satisfied, so nothing ever started the window manager.
run aerospace why="the window manager has to be running, and has to be restarted when its binary changes" \
    check='pgrep -qx AeroSpace && ! restart_pending AeroSpace' \
    apply='zsh recipes/aerospace-restart.zsh && restart_done AeroSpace'
