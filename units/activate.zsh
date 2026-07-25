requires=(aerospace alttab ainto karabiner dock input menubar bitwarden dotfiles)

service Dock           kind=killall
service AltTab
service LinearMouse
service Hammerspoon    path=/Applications/Hammerspoon.app
# No Karabiner-Menu service: karabiner.json hides its icon, so it quits on its
# own the moment it starts. The stop in the dotfiles unit is all that is needed.

run activate why="restart AeroSpace, borders, Ainto, Easydict (workspace-launch)" \
    check=always apply='zsh workspace-launch'
