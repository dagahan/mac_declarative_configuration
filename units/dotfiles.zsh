requires=(ohmyzsh)

link config/zsh/.zprofile                "$HOME/.zprofile"
link config/zsh/.zshrc                   "$HOME/.zshrc"
link config/aerospace/aerospace.toml     "$HOME/.aerospace.toml"
link config/kitty/kitty.conf             "$HOME/.config/kitty/kitty.conf"
# Karabiner's menu-bar icon comes from karabiner.json, so its menu app has to be
# down while the link changes; it is restarted in the activate unit.
link config/karabiner/karabiner.json     "$HOME/.config/karabiner/karabiner.json" stop_app=Karabiner-Menu
link config/linearmouse/linearmouse.json "$HOME/.config/linearmouse/linearmouse.json"
link config/nvim                         "$HOME/.config/nvim"
link config/borders/bordersrc            "$HOME/.config/borders/bordersrc"
