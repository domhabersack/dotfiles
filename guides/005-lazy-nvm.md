# Lazy NVM loading for fast shell startup

## What changed

`nvm.sh` is no longer sourced when the shell starts. Instead, stub functions for `nvm`, `node`, `npm`, and `npx` load the real NVM on first use, then call through to the real command.

```zsh
_load_nvm() {
  unset -f nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { _load_nvm; nvm  "$@"; }
node() { _load_nvm; node "$@"; }
npm()  { _load_nvm; npm  "$@"; }
npx()  { _load_nvm; npx  "$@"; }
```

## Why it helps

Sourcing `nvm.sh` at shell startup typically adds 200–500ms to every new terminal or tmux pane. When you open many panes in a day, that latency compounds. With lazy loading, new shells start almost instantly — NVM only pays its cost the first time you actually use it in that session.

## When to use it

This is invisible when it's working. You call `node`, `npm`, `nvm use`, etc. exactly as before. The only difference is a very slight delay on the *first* call in a new shell while NVM loads.

## What to look out for

- **Scripts that rely on `.nvmrc` auto-switching** won't fire on `cd` — NVM's directory hook (`nvm use --auto`) requires NVM to be fully loaded to work. If you use `nvm use` in project-specific hooks, those will trigger the lazy load automatically, but `.nvmrc` auto-use on `cd` won't function until after the first NVM call.
- **If you need NVM available immediately** (e.g., in a script that sources `.zshrc`), the lazy stubs work fine — the script just pays the load cost on the first call.
- Calling `type node` or `which node` before NVM loads will report the stub, not the real binary path.
