################
# EXPORTS      #
################

export NODE_PATH=/usr/local/share/npm/lib/node_modules
export PATH=/usr/local/share/npm/bin:/opt/local/bin:/opt/local/sbin:/opt/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/local/git/bin:/usr/local/opt/coreutils/libexec/gnubin:$PATH

# Android-SDK
export ANDROID_HOME=/usr/local/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools

################
# RBENV        #
################

# add `rbenv init` to shell to enable shims and autocompletion
eval "$(rbenv init -)"


################
# AUTOCOMPLETE #
################

# enable autocomplete
autoload -U compinit && compinit

# case-insensitive (all),partial-word and then substring completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'


################
# COLORS       #
################

# enable colors
autoload -U colors && colors

# colors used in `ls`
export LSCOLORS="Gxfxcxdxbxegedabagacad"


################
# HISTORY      #
################

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000


################
# EDITOR       #
################

# set editor
export EDITOR='vim'


################
# PROMPT       #
################

setopt prompt_subst

#
# git
#

GIT_PROMPT_PREFIX="%{$fg[white]%}[%{$reset_color%}"
GIT_PROMPT_SUFFIX="%{$fg[white]%}]%{$reset_color%}"
GIT_PROMPT_AHEAD="%{$fg[cyan]%}↑NUM%{$reset_color%}"
GIT_PROMPT_BEHIND="%{$fg[cyan]%}↓NUM%{$reset_color%}"
GIT_PROMPT_MERGING="%{$fg[magenta]%}⚡︎%{$reset_color%}"
GIT_PROMPT_UNTRACKED="%{$fg[red]%}●%{$reset_color%}"
GIT_PROMPT_MODIFIED="%{$fg[yellow]%}●%{$reset_color%}"
GIT_PROMPT_STAGED="%{$fg[green]%}●%{$reset_color%}"

# show branch/tag or name-rev if on detached head
parse_git_branch() {
  (git symbolic-ref -q HEAD || git name-rev --name-only --no-undefined --always HEAD) 2> /dev/null
}

# show different symbols as appropriate for various repository states
parse_git_state() {
  # compose value via multiple conditional appends
  local GIT_STATE=""

  local NUM_AHEAD="$(git log --oneline @{u}.. 2> /dev/null | wc -l | tr -d ' ')"
  if [ "$NUM_AHEAD" -gt 0 ]; then
    GIT_STATE=$GIT_STATE${GIT_PROMPT_AHEAD//NUM/$NUM_AHEAD}
  fi

  local NUM_BEHIND="$(git log --oneline ..@{u} 2> /dev/null | wc -l | tr -d ' ')"
  if [ "$NUM_BEHIND" -gt 0 ]; then
    GIT_STATE=$GIT_STATE${GIT_PROMPT_BEHIND//NUM/$NUM_BEHIND}
  fi

  local GIT_DIR="$(git rev-parse --git-dir 2> /dev/null)"
  if [ -n $GIT_DIR ] && test -r $GIT_DIR/MERGE_HEAD; then
    GIT_STATE=$GIT_STATE$GIT_PROMPT_MERGING
  fi

  if ! git diff --cached --quiet 2> /dev/null; then
    GIT_STATE=$GIT_STATE$GIT_PROMPT_STAGED
  fi

  if ! git diff --quiet 2> /dev/null; then
    GIT_STATE=$GIT_STATE$GIT_PROMPT_MODIFIED
  fi

  if [[ -n $(git ls-files --other --exclude-standard 2> /dev/null) ]]; then
    GIT_STATE=$GIT_STATE$GIT_PROMPT_UNTRACKED
  fi

  if [[ -n $GIT_STATE ]]; then
    echo "$GIT_STATE"
  fi
}

# prints branch and state if in git repository
git_prompt_string() {
  local git_where="$(parse_git_branch)"
  [ -n "$git_where" ] && echo "$(parse_git_state)$GIT_PROMPT_PREFIX%{$fg[cyan]%}${git_where#(refs/heads/|tags/)}%{$reset_color%}$GIT_PROMPT_SUFFIX"
}

#
# rbenv
#

RBENV_PROMPT_PREFIX=" "
RBENV_PROMPT_SUFFIX=""

# show current rbenv version if different from rbenv global
rbenv_prompt_string() {
  local ver=$(rbenv version-name)
  [ "$(rbenv global)" != "$ver" ] && echo "$RBENV_PROMPT_PREFIX%{$fg[red]%}${ver}%{$reset_color%}$RBENV_PROMPT_SUFFIX"
}

# set left-hand prompt
PS1='%{$fg[cyan]%}%~ %{$fg[green]%}%#%{$reset_color%} '

# set right-hand prompt
RPS1='$(git_prompt_string)$(rbenv_prompt_string)'


################
# FUNCTIONS    #
################

# create directory and change to it
md() {
  mkdir -p "$@" && cd "$@"
}


################
# ALIASES      #
################

# always use color in `grep`
alias grep='grep --color'

# always use color in `ls`
alias ls='ls -G'
alias la='ls -la'

# git
alias ga='git add'
alias gb='git branch'
alias gc='git commit'
alias gco='git checkout'
alias gd='git diff'
alias gl='git llog'
alias gm='git merge'
alias gr='git rm'
alias grb='git rebase'
alias grbc='git add . && git rebase --continue'
alias grbs='git rebase --skip'
alias gst='git status -s'

# do not allow scripts to automatically delete things for you
alias rm='rm -i'

# SVN
alias svn='colorsvn'

# tmux
alias tmuxinit='~/.tmux/environments/default'
