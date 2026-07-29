# fzf-tab: fuzzy tab-completion menus

## What changed

[fzf-tab](https://github.com/Aloxaf/fzf-tab) now auto-clones into `~/.zsh/plugins/fzf-tab` on first shell start, the same self-installing pattern as `zsh-autosuggestions` and `zsh-syntax-highlighting`. It's sourced right after `compinit` and before those two plugins.

## Why it helps

Zsh's default tab-completion menu is a flat list you cycle through with Tab or the arrow keys. fzf-tab replaces it with an interactive, fuzzy-filterable popup — completing a long list of git branches, npm scripts, or CLI flags now works like fzf itself: type a fragment, narrow the list, hit Enter.

## When to use it

Anywhere completion already kicks in — `git checkout <Tab>`, `ssh <Tab>`, option flags, file paths with many candidates. Nothing to invoke deliberately; it replaces the existing Tab behavior everywhere.

## What to look out for

- Load order matters: fzf-tab must be sourced after `compinit` and before `zsh-autosuggestions`/`zsh-syntax-highlighting`. This is already how `zshrc` is laid out — don't reorder the PLUGINS section.
- Auto-clones from GitHub on first shell start, same as the other zsh plugins. On a machine with no internet access on that first run, it'll be missing until you clone it manually into `~/.zsh/plugins/fzf-tab`.
- Once the fzf popup is open, navigation is fzf's own (arrow keys / Ctrl-J/K, Enter to accept) rather than zsh's normal completion-menu keys.
