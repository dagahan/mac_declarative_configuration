export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git)

source "$ZSH/oh-my-zsh.sh"

alias cls='clear'
alias la='ls -a'
alias mac="$HOME/mac_setup/mac"
alias mac-sync="$HOME/mac_setup/mac sync"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/nick/.lmstudio/bin"
# End of LM Studio CLI section

