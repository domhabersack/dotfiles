# Dominik Habersack's Dot Files

Customizations of several command-line utilities.

## Setup

Clone this repository to `~/.dotfiles`:

```sh
git clone <repo-url> ~/.dotfiles
```

Symlink each dotfile from your home directory:

```zsh
for f (gitconfig tmux.conf vimrc zshrc) ln -s ~/.dotfiles/$f ~/.$f
```

For neovim, also create the config directory symlink:

```zsh
brew install neovim ripgrep fd tree-sitter-cli
mkdir -p ~/.config/nvim
ln -s ~/.dotfiles/vimrc ~/.config/nvim/init.vim
```

`tree-sitter-cli` is required for syntax highlighting: the `main` branch of
nvim-treesitter compiles parsers with it. Note it is a **separate** formula from
`tree-sitter` (which is library-only), and the CLI must come from a package
manager, not npm.

On first `nvim` launch, vim-plug installs all plugins automatically. Language servers (tsserver, tailwindcss-language-server, eslint, etc.) are then installed by mason on the second launch — check progress with `:Mason`.

### Machine-specific settings

Some files are not committed to this repository and must be created on each machine for settings that should not be shared (paths with usernames, credentials, machine-specific tools):

| File | Purpose |
|------|---------|
| `~/.gitignore_global` | machine-specific global git ignores |
| `~/.gitconfig.local` | name, email, signing keys, machine-specific credentials |
| `~/.tmux.conf.local` | local tmux overrides |
| `~/.vimrc.local` | local vim settings |
| `~/.zshrc.local` | machine-specific paths, environment variables, aliases |
| `~/.dotfiles/window-colors` | tmux window color groups (differs per machine — see below) |

Each has a corresponding `.sample` file with placeholder values to use as a starting point. Create the file from each sample, then symlink it into your home directory:

```zsh
cp ~/.dotfiles/gitignore_global.sample ~/.dotfiles/gitignore_global
ln -s ~/.dotfiles/gitignore_global ~/.gitignore_global
for f (gitconfig tmux.conf vimrc zshrc) cp ~/.dotfiles/$f.local.sample ~/.dotfiles/$f.local
for f (gitconfig tmux.conf vimrc zshrc) ln -s ~/.dotfiles/$f.local ~/.$f.local
```

`window-colors` is read in place from `~/.dotfiles/` (no symlink needed) by
`bin/tmux-color-windows`, so just copy the sample:

```zsh
cp ~/.dotfiles/window-colors.sample ~/.dotfiles/window-colors
```

Then edit it to list this machine's own window-name groups and colors.

The window list also shows a 🔔 next to any background window whose pane rings
the terminal bell (e.g. Claude Code waiting for input). That relies on the
program emitting an actual bell character — for Claude Code, set
`"preferredNotifChannel": "terminal_bell"` in `~/.claude/settings.json`.
Without it, Claude uses desktop notifications instead and the 🔔 never appears.

Similarly, `<prefix> w` (`choose-tree`, wired up in `tmux.conf.local`) can show
your account-wide Claude Code quota (5-hour and weekly, as in `/usage`) on each
session row via `bin/tmux-usage-statusline`. That script only reads
`~/.claude/.usage-cache.json` — nothing writes it by default. Add a `statusLine`
hook in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

and fold this into `~/.claude/statusline.sh` (Claude Code pipes a JSON payload
into its `statusLine` command on every turn; this pulls the `rate_limits` field
out of it and caches it for readers outside the session, like tmux):

```sh
#!/bin/bash
input=$(cat)

if echo "$input" | jq -e '.rate_limits.five_hour' >/dev/null 2>&1; then
  _uc_file="$HOME/.claude/.usage-cache.json"
  _uc_new=$(echo "$input" | jq -c '.rate_limits')
  _uc_old='{}'
  if [ -f "$_uc_file" ] && jq -e . "$_uc_file" >/dev/null 2>&1; then
    _uc_old=$(cat "$_uc_file")
  fi
  # Guard against an idle session's stale (lower) snapshot clobbering a
  # busier session's fresher (higher) one: only accept a write if the window
  # rolled over (resets_at changed) or the percentage didn't go backwards.
  _uc_accept=$(jq -n --argjson new "$_uc_new" --argjson old "$_uc_old" '
    def fresher(key):
      ($new[key].resets_at // 0) != ($old[key].resets_at // -1)
      or ($new[key].used_percentage // 0) >= ($old[key].used_percentage // 0);
    fresher("five_hour") and fresher("seven_day")
  ')
  if [ "$_uc_accept" = "true" ]; then
    _uc_tmp="$_uc_file.$$"
    echo "$_uc_new" > "$_uc_tmp" && mv -f "$_uc_tmp" "$_uc_file"
  fi
fi
```

The cache is account-wide and shared across every Claude Code session, so it
only refreshes while at least one session is active; `tmux-usage-statusline`
appends an age marker once it's gone stale for more than 15 minutes, and
prints `Claude quota: n/a` if the cache file doesn't exist yet. This snippet
only handles the caching — fold it into whatever your `statusLine` command
already renders for its own per-turn display.

Each window-list entry also starts with a four-cell **freshness bar** showing how
recently that window was accessed, filling right-to-left from `░░░░` (not touched
in weeks) up through `░░░▒`, `░░░▓`, `░░░█`, `░░▒█` … to `████` (just now) — 13
stages, each cell stepping `░ → ▒ → ▓ → █`. `bin/tmux-freshness-windows` stamps the
active window with the current time and maps every window's elapsed time onto the
bar on a **logarithmic** scale (fine-grained over the first minutes/hours, then
fading slowly out to ~2 weeks); `bin/tmux-freshness-watch` re-renders on a timer so
the bars decay even when idle. The bar is decorative only — like a leading marker
emoji, it is not part of the window name, so it never affects window sorting or
coloring.

### Plugins (auto-installed)

On first shell/editor start, plugins install themselves automatically:

- **fzf** + **zsh-autosuggestions** + **zsh-syntax-highlighting** — cloned by `zshrc` on first shell start (same pattern as TPM in `tmux.conf`).
- **vim-plug** — bootstrapped by `vimrc` on first `nvim` launch; all plugins install automatically.
- **Language servers** (tsserver, tailwindcss, eslint, cssls, html, jsonls) — installed by mason on the second `nvim` launch.

### Optional tools

- `brew install zoxide` — smart `cd` with frecency; auto-activated if present.
- `brew install lazygit` — bound to `prefix g` in tmux, opening in a floating popup.
- `brew install mosh` — drop-in `ssh` replacement that survives network drops/roaming; use `mosh user@host` in place of `ssh` on flaky connections.
- `npm install -g ccusage` — Claude Code token/cost tracker; bound to `prefix u` in tmux, opening the current billing block's usage in a floating popup.

## Contents

* gitconfig - aliases, colors
* tmux.conf - remapped prefix, simple status bar, clear pane-highlighting
* vimrc - syntax highlighting, line numbers, coloring, gutter, soft tabs; neovim LSP (TypeScript, Tailwind, ESLint, Prettier on save)
* zshrc - aliases, colors, functions, sexy prompt

## Highlights

Some of the most useful elements of these dotfiles are:

- `git llog` (or `gl`) for a lovely git log
- `md DIRECTORY` to create a directory and change to it
- git- and rbenv-information in prompt
- **Ctrl-R** fuzzy history search (fzf) — biggest win for SSH from mobile
- **Shared history** across tmux panes and SSH sessions — commands appear everywhere immediately
- **Lazy nvm** — shell starts fast; nvm loads only when you first call `node`/`npm`/`npx`/`nvm`
- **Autosuggestions** — ghost-text completions reduce typing, especially on mobile keyboards
- **TypeScript LSP in neovim** — tsserver + Tailwind autocomplete, errors-as-you-type, goto-definition, rename, prettier on save; same language servers as VS Code

## Screenshots

### zsh prompt

![zsp prompt](/assets/images/zsh-prompt.png)

### Lovely git log (`git llog`/`gl`)

![git llog](/assets/images/git-llog.png)
