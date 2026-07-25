export PATH="/opt/homebrew/bin:$PATH"
aerospace reload-config 2>/dev/null && print -r -- "  aerospace config reloaded"
pkill -USR1 -x kitty 2>/dev/null && print -r -- "  kitty reloaded"
launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server" 2>/dev/null \
    && print -r -- "  karabiner console user server restarted"
exit 0
