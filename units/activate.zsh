requires=(aerospace alttab ainto easydict karabiner dock input menubar bitwarden dotfiles inputlock desk)
workspace=1

service Dock        kind=killall
service AltTab
service Hammerspoon path=/Applications/Hammerspoon.app
service Ainto
service Easydict
service InputLock path=/Applications/InputLock.app
# No Karabiner-Menu service: karabiner.json hides its icon, so it quits on its
# own the moment it starts. The stop in the dotfiles unit is all that is needed.

run borders why="focused-window outline daemon (JankyBorders)" \
    check='pgrep -qx borders' \
    apply='zsh recipes/borders.zsh' \
    revert='pkill -x borders; true'

# Liveness first, restart second. Checking only for a pending restart meant a
# dead AeroSpace looked satisfied, so nothing ever started the window manager.
run aerospace why="the window manager has to be running, and has to be restarted when its binary changes" \
    check='pgrep -qx AeroSpace && ! restart_pending AeroSpace' \
    apply='zsh recipes/aerospace-restart.zsh && restart_done AeroSpace' \
    revert='/opt/homebrew/bin/aerospace enable off 2>/dev/null; pkill -x AeroSpace; true'

# The laptop panel. A run, not a daemon: mac workspace down skips daemons, and down is what
# must turn the panel back on and unload both jobs.
run desk why="the laptop panel goes dark while monitors are attached, and a new build needs the agent reloaded" \
    check='zsh recipes/desk.zsh check && ! restart_pending mac-desk' \
    apply='zsh recipes/desk.zsh up && restart_done mac-desk' \
    revert='zsh recipes/desk.zsh down'
