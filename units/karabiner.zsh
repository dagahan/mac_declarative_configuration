requires=(brew dotfiles)

run karabiner-driver why="the virtual HID driver extension must be activated once" \
    check='pgrep -qf karabiner_console_user_server' \
    apply='"/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager" activate && open -g -j -a Karabiner-Elements && sleep 4'

manual karabiner-permissions \
    do="System Settings > Login Items & Extensions: enable the Karabiner driver extension and both background agents; Privacy > Accessibility: enable Karabiner-Core-Service" \
    detect='grep -q "monitor is started (grabbed)" /var/log/karabiner/core_service.log'
