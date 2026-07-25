requires=(brew)

run redmi-hotkey why="ctrl+cmd+s screenshot block inside ~/.hammerspoon/init.lua" \
    check='grep -q "redmi_pad_screenshot_to_clip_board BEGIN" "$HOME/.hammerspoon/init.lua"' \
    apply='zsh vendor/macos_automation_scripts/redmi_pad_screenshot_to_clip_board/install_hotkey.sh'

run hammerspoon-login-item why="Hammerspoon starts from mac restart, not from a login item" \
    check='! osascript -e "tell application \"System Events\" to get name of every login item" 2>/dev/null | grep -q Hammerspoon' \
    apply='osascript -e "tell application \"System Events\" to delete login item \"Hammerspoon\""'

manual hammerspoon-accessibility \
    do="System Settings > Privacy & Security > Accessibility: enable Hammerspoon (needed for the global hotkey)"
