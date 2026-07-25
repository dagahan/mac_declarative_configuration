requires=(brew alttab)

run menubar why="menu bar icon + autostart prefs for AltTab, LinearMouse, Hammerspoon" \
    check=always apply='zsh modules/48-menubar-icons.sh'
