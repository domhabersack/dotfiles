################
# EXPORTS      #
################

# none


################
# NVM          #
################

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


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

# set left-hand prompt
PS1='%{$fg[cyan]%}%~ %{$fg[green]%}%#%{$reset_color%} '

# set right-hand prompt
RPS1='$(git_prompt_string)'


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

# use color in `grep`, add line numbers, search directories recursively, ignore vim binary files
alias grep='grep --binary-file=without-match --color --directories=recurse --line-number'

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

# tmux
alias tmuxinit='~/.tmux/environments/default'
