export PATH="/opt/homebrew/bin:$PATH"
[[ -x "$HOME/.config/borders/bordersrc" ]] || { print -ru2 -- "bordersrc not linked"; exit 1 }
"$HOME/.config/borders/bordersrc" &>/dev/null &!
sleep 0.6
pgrep -qx borders
