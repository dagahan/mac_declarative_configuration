# Karabiner intercepts Cmd+Space before Spotlight sees it, so Spotlight's own
# symbolic hotkey (id 64) must stay at its default enabled state.
plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
value="$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" "$plist" 2>/dev/null)"

case "${1:-check}" in
    check) [[ "$value" =~ ^(false|0)$ ]] && exit 1; exit 0 ;;
    apply)
        defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
            '{ enabled = 1; value = { parameters = (32, 49, 1048576); type = standard; }; }'
        /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null
        exit 0 ;;
esac
