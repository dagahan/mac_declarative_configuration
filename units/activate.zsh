requires=(aerospace alttab ainto karabiner dock input menubar bitwarden dotfiles)

service Dock        kind=killall
service AltTab
service LinearMouse
service Hammerspoon path=/Applications/Hammerspoon.app
service Ainto
# No Karabiner-Menu service: karabiner.json hides its icon, so it quits on its
# own the moment it starts. The stop in the dotfiles unit is all that is needed.

run aerospace-restart why="restart AeroSpace, preserving the focused workspace" \
    check='! restart_pending AeroSpace' \
    apply='zsh recipes/aerospace-restart.zsh && restart_done AeroSpace'

run activate why="borders, Easydict and karabiner services (workspace-launch)" \
    check=always apply='zsh workspace-launch'
