export PATH="/opt/homebrew/bin:$PATH"

# Only the live-config re-reads. Starting whatever is down is the activate
# unit's job, which `mac reload` runs before this.
if pgrep -qx AeroSpace; then
    aerospace reload-config 2>/dev/null && print -r -- "  aerospace config reloaded"
else
    print -r -- "  aerospace is not running — see the errors above"
fi
pkill -USR1 -x kitty 2>/dev/null && print -r -- "  kitty reloaded"
launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server" 2>/dev/null \
    && print -r -- "  karabiner console user server restarted"
exit 0
