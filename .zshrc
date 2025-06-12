# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="bira"

# Set list of themes to pick from when loading at random


# Uncomment the following line to change how often to auto-update (in days).

ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files

plugins=(
	git
	fzf
	vscode
	z
	zsh-autosuggestions
	zsh-autocomplete
	zsh-syntax-highlighting
)

# Autocompletion settings
#zstyle ':completion:*' menu select
#zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zle -N insert-unambiguous-or-complete
zle -N menu-search
zle -N recent-paths

source $ZSH/oh-my-zsh.sh

# User configuration

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes.
alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

# vim and emacs
alias vim='nvim'

# Changing "ls" to "exa"
alias ls='exa -al --color=always --group-directories-first'
alias la='exa -a --color=always --group-directories-first'
alias ll='exa -l --color=always --group-directories-first'
alias lt='exa -aT --color=always --group-directories-first'
alias l.='exa -a | egrep "^\."'

# rpm-ostree
alias upall='sudo apt upgrade -y'
alias upcheck='sudo apt update'

# Colorize grep output
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# confirm before overwriting something
alias cp="cp -i"
alias mv='mv -i'
alias rm='rm -i'

# adding flags
alias df='df -h'
alias free='free -m'

# ps
alias psa="ps auxf"
alias psgrep="ps aux | grep -v grep | grep -i -e VSZ -e"
alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'

# Merge Xresources
alias merge='xrdb -merge ~/.Xresources'

# git
alias addup='git add -u'
alias addall='git add .'
alias branch='git branch'
alias checkout='git checkout'
alias clone='git clone'
alias commit='git commit -m'
alias fetch='git fetch'
alias pull='git pull origin'
alias push='git push origin'
alias tag='git tag'
alias newtag='git tag -a'

# system reporting
neofetch

# adding go and fabric paths
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:/home/$USER/go/bin

# some define alias for fabric user frindly approach
alias ytsum='function _ytsum() { fabric -y "$1" --pattern youtube_summary | glow; }; _ytsum'
alias claims='xclip -selection clipboard -o | fabric --stream --pattern analyze_claims | glow'
alias summarize='xclip -selection clipboard -o | fabric --stream --pattern summarize | glow'
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
