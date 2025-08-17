# zmodload zsh/zprof

alias stow="stow -d ~/Documents/dotty -t ~"

# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"


plug "zsh-users/zsh-autosuggestions"
plug "zap-zsh/supercharge"
plug "zap-zsh/zap-prompt"
plug "zsh-users/zsh-syntax-highlighting"
plug "chivalryq/git-alias"

# Load and initialise completion system
autoload -Uz compinit
compinit

# ls lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

alias vim=nvim


export EDITOR=nvim


export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOPATH:$GOBIN

load_nvm () {
	plug "zap-zsh/nvm"
}

# zprof
