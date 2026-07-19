export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git)

source "$ZSH/oh-my-zsh.sh"

alias cls='clear'
alias la='ls -a'
alias mac-sync="$HOME/mac_setup/sync"
alias mac-workspace-launch="$HOME/mac_setup/workspace-launch"
alias mac-workspace-launch-force="$HOME/mac_setup/workspace-launch --force"
