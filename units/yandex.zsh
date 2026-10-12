requires=(base)

run yandex-screenshot-hotkeys stop_app=Yandex \
    why="Yandex Browser's screenshot tool takes ctrl+option+1-3, which Karabiner sends for option+1-3" \
    check='zsh recipes/yandex-screenshot-hotkeys.zsh check' \
    apply='zsh recipes/yandex-screenshot-hotkeys.zsh off' \
    revert='zsh recipes/yandex-screenshot-hotkeys.zsh on'
