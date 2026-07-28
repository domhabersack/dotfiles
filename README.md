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

For Claude Code specifically, three notification types get their own emoji
instead of the generic 🔔: 🔐 for a pending permission prompt or an MCP
elicitation dialog (both are "blocked, waiting on you" states — just from
different subsystems), 💬 for an idle prompt (task done, waiting on you). Add
this to the `hooks` key in `~/.claude/settings.json` (merge it if the key
already exists):

```json
"hooks": {
  "Notification": [
    { "matcher": "permission_prompt",   "hooks": [{ "type": "command", "command": "~/.dotfiles/bin/tmux-claude-notify approval" }] },
    { "matcher": "idle_prompt",         "hooks": [{ "type": "command", "command": "~/.dotfiles/bin/tmux-claude-notify idle" }] },
    { "matcher": "elicitation_dialog",  "hooks": [{ "type": "command", "command": "~/.dotfiles/bin/tmux-claude-notify approval" }] }
  ]
}
```

The other notification types (`auth_success`, `elicitation_complete`,
`elicitation_response`, `agent_needs_input`, `agent_completed`) are left to
fall back to the plain 🔔: the first three are transient acknowledgements
with no state worth persisting on a window, and the last two describe a
different background session rather than the pane's own window.

`bin/tmux-claude-notify` falls back to tmux's well-known install paths if
`tmux` isn't on `PATH` — worth knowing if your `~/.claude/settings.json` sets
a custom `env.PATH` that excludes it, as this one does. It also skips
stamping a window you're currently attached to and looking at: notifications
refire on nearly every turn of an active conversation, far faster than the
window-selection event that clears the emoji, so flagging the foreground
window would just show a stuck-looking indicator rather than a useful one.

Similarly, `<prefix> w` (`choose-tree`, wired up in `tmux.conf`) can show
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

Similarly, `<prefix> T` opens a popup (`bin/tmux-obsidian-task-list`) listing
every open task across your Obsidian daily notes, grouped by project tag and
sorted oldest-first; and each window-list entry in `<prefix> w` shows a bold
name plus a `done/total` count while tasks tagged `#<window-slug>` are open
in any daily note (`bin/tmux-obsidian-tasks`, kept live by
`bin/tmux-obsidian-watch`, an `fswatch` daemon — `brew install fswatch`, or
this degrades to updating only on window create/rename). Both features
require `TMUX_OBSIDIAN_DAILY_DIR` (set in `~/.zshrc.local`) to point at a
directory of daily notes — one `.md` file per day with `- [ ]`/`- [x]` lines,
with the popup restricted to a `## Tasks` heading — and are fully disabled, with no popup
binding and no window annotations, when it's unset. Per-project popup header
colors reuse `~/.dotfiles/window-colors`, the same file `bin/tmux-color-windows`
reads, so the two views can never disagree on a project's color. Note that
tmux only picks up newly-exported environment variables when its server
(re)starts — after first setting `TMUX_OBSIDIAN_DAILY_DIR`, a plain
`<prefix> r` config reload isn't enough; kill and restart the tmux server (or
just reboot/relogin).

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

`status-left` shows open PR and Dependabot-vulnerability counts for whichever
repo the currently active pane is in, e.g.:

```
dotfiles 3 PRs (2 human, 1 bot) · 5 vulnerabilities (2 critical, 1 high, 2 medium)
```

via `bin/tmux-repo-pr` (the renderer, triggered on window/pane switches and a
background ticker) and `bin/tmux-repo-pr-fetch` (the only thing that touches
the network — two read-only `gh api` calls, no mutating calls of any kind).
Both halves mirror
[`mission-status`](https://github.com/sueddeutsche/mission-status)'s
classification and severity color scheme, translated from raw ANSI to tmux's
native `#[fg=...]` style tags:

- **PRs** split human vs. bot (a `dependabot/`/`renovate/` branch prefix or
  matching bot login counts as bot), mirroring `IsBotPR`.
- **Vulnerabilities** are open Dependabot alerts, deduplicated by package
  (multiple CVEs on the same dependency collapse to one entry at its highest
  severity, mirroring `deduplicateAlerts`) and bucketed by severity —
  critical (`colour196`, red), high (`colour208`, orange), medium
  (`colour220`, yellow), low (`colour94`, dark yellow/brown), unknown (dim) — shown
  highest-severity-first, only non-zero buckets. Zero shows a reassuring
  green (`colour34`) `no known vulnerabilities` rather than nothing, so you
  can tell the check ran.

PR listing and vulnerability-alert access are **independent GitHub
permissions** — a repo can allow one and deny the other (PRs are visible to
anyone with read access; alerts need collaborator-level access on that
specific repo) — so each half is fetched, cached, and rendered independently:
a repo shows PRs only, vulnerabilities only, both, or (most commonly, for a repo this
account isn't a collaborator on) neither, with no crash or error text either
way. Also degrades to rendering nothing if `gh` is missing, the pane isn't
inside a git repo, the repo has no remote, or the active window belongs to a
detached session.

Requires the `gh` CLI installed and `gh auth login` run once. Results are
cached per-repo under `~/.cache/tmux-repo-pr/` so the status bar never blocks
on the network: a repo seen for the first time shows a loading indicator
while the background fetch runs, and every render after that shows the last
cached values instantly, refreshing in the background roughly every 5
minutes (15 minutes if either half errored, so an inaccessible repo isn't
reprobed every tick). No Claude/settings.json hook needed — this is
independent of the quota feature above.

### Plugins (auto-installed)

On first shell/editor start, plugins install themselves automatically:

- **fzf** + **fzf-tab** + **zsh-autosuggestions** + **zsh-syntax-highlighting** — cloned by `zshrc` on first shell start (same pattern as TPM in `tmux.conf`).
- **vim-plug** — bootstrapped by `vimrc` on first `nvim` launch; all plugins install automatically.
- **Language servers** (tsserver, tailwindcss, eslint, cssls, html, jsonls) — installed by mason on the second `nvim` launch.

### Optional tools

- `brew install zoxide` — smart `cd` with frecency; auto-activated if present.
- `brew install lazygit` — bound to `prefix g` in tmux, opening in a floating popup.
- `brew install mosh` — drop-in `ssh` replacement that survives network drops/roaming; use `mosh user@host` in place of `ssh` on flaky connections.
- `npm install -g ccusage` — Claude Code token/cost tracker; bound to `prefix u` in tmux, opening the current billing block's usage in a floating popup.
- `brew install git-delta` — syntax-highlighted, line-level diffs for `git diff`/`git log`/`git show`; falls back to git's plain output if not installed.
- `brew install bat` — colorized `cat`/man-page replacement; also powers the preview pane in fzf's Ctrl-T file picker.
- [`gh`](https://cli.github.com) + `gh auth login` — powers the per-repo open-PR count in `status-left` (see above); read-only, degrades to nothing without it.

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
