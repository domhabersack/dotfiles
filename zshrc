################
# NVM          #
################

# lazy-load: shims defer the slow nvm.sh source until first use
export NVM_DIR="$HOME/.nvm"
_load_nvm() {
  unset -f nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { _load_nvm; nvm  "$@"; }
node() { _load_nvm; node "$@"; }
npm()  { _load_nvm; npm  "$@"; }
npx()  { _load_nvm; npx  "$@"; }


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

# prefer GNU color flag (Linux); fall back to BSD -G (macOS)
if ls --color=auto > /dev/null 2>&1; then
  alias ls='ls --color=auto'
  export LS_COLORS='di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'
else
  alias ls='ls -G'
  export LSCOLORS='Gxfxcxdxbxegedabagacad'
fi


################
# HISTORY      #
################

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt EXTENDED_HISTORY       # save timestamp with each entry
setopt INC_APPEND_HISTORY     # write immediately, not on shell exit
setopt SHARE_HISTORY          # share across all open sessions (tmux panes, SSH)
setopt HIST_IGNORE_ALL_DUPS   # drop older duplicates
setopt HIST_REDUCE_BLANKS     # collapse extra whitespace
setopt HIST_VERIFY            # show !-expansion before running
setopt HIST_IGNORE_SPACE      # leading space keeps command out of history


################
# OPTIONS      #
################

setopt AUTO_CD                # type dirname to cd into it
setopt AUTO_PUSHD             # cd pushes onto directory stack
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS   # allow # comments in interactive shell
setopt EXTENDED_GLOB
setopt NO_BEEP

bindkey -e                    # emacs key bindings (Ctrl-A/E/R/W/U etc.)
bindkey '^[[1;5C' forward-word   # Ctrl-Right
bindkey '^[[1;5D' backward-word  # Ctrl-Left
bindkey '^[f'     forward-word   # Alt-F (Terminus iOS)
bindkey '^[b'     backward-word  # Alt-B (Terminus iOS)


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
# uses a single `git status` call instead of multiple git invocations
parse_git_state() {
  local status_out state=""
  status_out="$(git status --porcelain=v2 --branch 2>/dev/null)" || return

  local git_dir
  git_dir="$(git rev-parse --git-dir 2>/dev/null)"

  local ahead behind staged modified untracked
  read -r ahead behind staged modified untracked < <(print -- "$status_out" | awk '
    /^# branch.ab/ {
      a=$3; b=$4
      gsub(/[^0-9]/, "", a); gsub(/[^0-9]/, "", b)
      ahead=a+0; behind=b+0
    }
    /^[12] [MADRC]/  { staged=1 }
    /^[12] .[MADRC]/ { modified=1 }
    /^\?/            { untracked=1 }
    END { print ahead+0, behind+0, staged+0, modified+0, untracked+0 }
  ')

  (( ahead    > 0 )) && state+=${GIT_PROMPT_AHEAD//NUM/$ahead}
  (( behind   > 0 )) && state+=${GIT_PROMPT_BEHIND//NUM/$behind}
  [[ -n $git_dir && -r "$git_dir/MERGE_HEAD" ]] && state+=$GIT_PROMPT_MERGING
  (( staged       )) && state+=$GIT_PROMPT_STAGED
  (( modified     )) && state+=$GIT_PROMPT_MODIFIED
  (( untracked    )) && state+=$GIT_PROMPT_UNTRACKED

  [[ -n $state ]] && echo "$state"
}

# prints branch and state if in git repository
git_prompt_string() {
  local git_where="$(parse_git_branch)"
  if [ -n "$git_where" ]; then
    local branch="${git_where#(refs/heads/|tags/)}"
    local state="$(parse_git_state)"
    echo "%{$reset_color%}:%{$fg[red]%}${branch}%{$reset_color%}${state:+ ${state}}"
  fi
}

# build the first prompt line before each prompt render
precmd() {
  print ""
  local line1=""

  [ -n "$SSH_CONNECTION" ] && line1="%{$fg[yellow]%}%m%{$reset_color%}"

  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$toplevel" ]; then
    local url repo
    url="$(git remote get-url origin 2>/dev/null)"
    if [ -n "$url" ]; then
      repo="${url##*/}"
      repo="${repo%.git}"
    else
      repo="$(basename "$toplevel")"
    fi
    [ -n "$line1" ] && line1+=" "
    line1+="%{$fg[cyan]%}${repo}$(git_prompt_string)"
  fi

  _LINE1="${line1}"$'\n'
}

# set left-hand prompt (multi-line)
PS1='${_LINE1}%{$fg[cyan]%}%~ %{$fg[green]%}%#%{$reset_color%} '

RPS1=''

# set terminal title to host:path when SSH'd; skip inside tmux to avoid
# conflicting with the alphabetical window-sort hook (tmux.conf:131-133)
if [[ -z "$TMUX" ]]; then
  _set_title() {
    if [[ -n "$SSH_CONNECTION" ]]; then
      print -Pn "\e]0;%m: %~\a"
    else
      print -Pn "\e]0;%~\a"
    fi
  }
  precmd_functions+=(_set_title)
fi


################
# TMUX         #
################

# Show 🦀 in the window list while Claude Code is running in that pane.
# preexec fires just before a command runs; precmd fires when the prompt returns.
if [[ -n "$TMUX" ]]; then
  _claude_preexec() {
    [[ "$1" != claude* ]] && return
    tmux set-option -p @tmux_claude 1 2>/dev/null
    ( ~/.dotfiles/bin/tmux-claude-windows >/dev/null 2>&1 & )
  }
  _claude_precmd() {
    local val
    val=$(tmux show-options -pqv @tmux_claude 2>/dev/null)
    [[ "$val" != 1 ]] && return
    tmux set-option -p @tmux_claude "" 2>/dev/null
    ( ~/.dotfiles/bin/tmux-claude-windows >/dev/null 2>&1 & )
  }
  preexec_functions+=(_claude_preexec)
  precmd_functions+=(_claude_precmd)
fi


################
# FUNCTIONS    #
################

# create directory and change to it
md() {
  mkdir -p -- "$1" && cd -- "$1"
}


################
# ALIASES      #
################

# use color in `grep`, add line numbers, search directories recursively, ignore vim binary files
alias grep='grep --binary-file=without-match --color --directories=recurse --line-number'

# ls with color (alias set in COLORS block above)
alias la='ls -la'

# git
alias ga='git add'
alias gb='git branch'
alias gc='git commit'
alias gco='git checkout'
alias gd='git diff'
alias gdw='git diff --word-diff=color'
alias gl='git llog'
alias gm='git merge'
alias gp='git push'
alias gp@='git push origin -u @'
alias gpo='git push origin'
alias gr='git rm'
alias grb='git rebase'
alias grbc='git add . && git rebase --continue'
alias grbs='git rebase --skip'
alias gst='git status -s'

# do not allow scripts to automatically delete things for you
alias rm='rm -i'


################
# PLUGINS      #
################

# fzf — fuzzy finder: Ctrl-R history search, Ctrl-T file picker, Alt-C cd
if [[ ! -d "$HOME/.fzf" ]] && command -v git >/dev/null 2>&1; then
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf" \
    && "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
fi
[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"

# zsh-autosuggestions and zsh-syntax-highlighting (auto-install on first run)
ZSH_PLUGIN_DIR="$HOME/.zsh/plugins"
for _p in zsh-autosuggestions zsh-syntax-highlighting; do
  if [[ ! -d "$ZSH_PLUGIN_DIR/$_p" ]] && command -v git >/dev/null 2>&1; then
    git clone --depth 1 "https://github.com/zsh-users/$_p.git" "$ZSH_PLUGIN_DIR/$_p"
  fi
done
unset _p
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
[ -f "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ] \
  && source "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
# syntax-highlighting must be sourced last
[ -f "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] \
  && source "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# zoxide — smart cd with frecency (install with: brew install zoxide)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"


################
# LOCAL        #
################

[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
