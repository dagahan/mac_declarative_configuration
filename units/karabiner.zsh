requires=(software dotfiles)
workspace=1

# The cask registers Karabiner's launchd jobs system-wide and enabled, so the
# remapper starts at boot no matter what this repo does. That is what makes an
# un-brought-up machine unusable: karabiner.json turns cmd+space into Ainto's
# hotkey, Ainto is not running, and there is no launcher and no Spotlight left.
# `mac workspace down` disables the jobs and the disabled state survives a
# reboot, so a machine nobody has brought up has a stock keyboard.
run karabiner-services root=1 \
    why="the remapper's launchd jobs, which the cask leaves enabled at boot" \
    check='pgrep -qf karabiner_console_user_server' \
    apply='zsh recipes/karabiner-services.zsh up' \
    revert='zsh recipes/karabiner-services.zsh down'

manual karabiner-permissions \
    do="System Settings > Login Items & Extensions: enable the Karabiner driver extension and both background agents; Privacy > Accessibility: enable Karabiner-Core-Service" \
    detect='grep -q "monitor is started (grabbed)" /var/log/karabiner/core_service.log'
