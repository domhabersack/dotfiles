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

Similarly, `<prefix> T` opens an interactive popup
(`bin/tmux-obsidian-task-picker`) listing every task — open and done — across
your Obsidian daily notes, grouped by project tag: `space`/`enter` flips the
highlighted task's checkbox in place in its note, `ctrl-h` hides/shows done
tasks (shown by default, dimmed), `ctrl-r` forces a refresh, and `esc` closes
the popup. A toggle writes straight to the note, so it shows up in Obsidian
immediately; conversely, editing a note directly in Obsidian while the popup
is open is picked up there within a few seconds, no keypress needed
(`bin/tmux-obsidian-task-poll`, on fzf's `every(5)`). This needs `fzf`
(see "Plugins (auto-installed)" below); without it, the popup falls back to
the previous read-only list (`bin/tmux-obsidian-task-list`, still grouped and
sorted oldest-first, but open tasks only, and un-toggleable). Each
window-list entry in `<prefix> w`
also shows a bold name plus a `done/total` count while tasks tagged
`#<window-slug>` are open in any daily note (`bin/tmux-obsidian-tasks`, kept
live by `bin/tmux-obsidian-watch`, an `fswatch` daemon — `brew install
fswatch`, or this degrades to updating only on window create/rename). All of
this requires `TMUX_OBSIDIAN_DAILY_DIR` (set in `~/.zshrc.local`) to point at
a directory of daily notes — one `.md` file per day with `- [ ]`/`- [x]`
lines, with the popup restricted to a `## Tasks` heading — and is fully
disabled, with no popup binding and no window annotations, when it's unset.
Per-project popup header colors reuse `~/.dotfiles/window-colors`, the same
file `bin/tmux-color-windows` reads, so the two views can never disagree on a
project's color. Note that tmux only picks up newly-exported environment
variables when its server (re)starts — after first setting
`TMUX_OBSIDIAN_DAILY_DIR`, a plain `<prefix> r` config reload isn't enough;
kill and restart the tmux server (or just reboot/relogin). A subsequent
`<prefix> r` (e.g. after a dotfiles update) is enough to pick up changes to
the binding itself.

Toggling a task writes directly to the note's file on disk; if that note is
open and has unsaved changes in Obsidian's editor at that exact moment,
Obsidian's own autosave can overwrite the toggle a couple of seconds later.
This is rare in practice (it requires the note to be both open and actively
being typed in) and bounded to that one checkbox, and the auto-refresh above
makes a reverted toggle visible within a few seconds rather than silently
lost — see `docs/superpowers/specs/2026-07-31-tmux-obsidian-task-popup-interactive-design.md`
for the full reasoning.

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

Each window-list entry also shows its git **branch** in dim parentheses after the
name, so a repo window reads `codeshots (main)` while a plain-directory window
stays `codeshots`. `bin/tmux-git-branch` resolves the label for a directory
(the current branch, or the short commit hash on a detached HEAD, or nothing
outside a work tree); `bin/tmux-git-branch-windows` stamps every window's
`@git_branch` from its active pane's path, refreshed on window
create/rename/select and by `bin/tmux-git-branch-watch` on a timer — the timer
is what catches a `git checkout` made in a window you then sit still in. Like
the freshness bar, the label is rendered at display time and is **not** part of
the window name, so it never affects sorting or coloring. The same
`@git_branch` also drives the active window's name row on the status bar (see
below), so a repo with no remote — where the PR/vulnerability line is empty —
still gets its `(branch)` there.

The status bar carries the active window's identity, the open PR for its
branch, and repo-wide health on up to four stacked rows (below the horizontal
rule):

1. **Name + branch** (`status-format[1]`, from `window_name` + `@git_branch`) —
   always present; the window name plus, in a git repo, its branch.
2. **Branch PR** (`status-format[2]`, from `@branch_pr`) — the open pull request
   whose head *is* the current branch, if one exists: its number, commit count,
   diff size, checks, review state, and unresolved conversations. This is "open work"
   visibility — the state of the PR the window in front of you is producing.
3. **Repo health** (`@repo_pr`, from `status-left`) — that repo's open-PR and
   Dependabot-vulnerability *counts* across the whole repo, kept off the name so
   it doesn't crowd it.

The branch-PR and health rows are independent axes and each shows only when it
has something; the branch-PR row sits above the health row, so when there's no
PR the health row slides up. For whichever repo the active pane is in, e.g.:

```
dotfiles (feat/foo)
PR #42 · 12 commits · 3 files · +120 -30 · all checks have passed · approved · 2 unresolved
3 PRs (2 human, 1 bot) · 5 vulnerabilities (2 critical, 1 high, 2 medium)
```

`bin/tmux-status-rows` sizes the bar to exactly what's on it — two rows (rule +
name) when neither content row has anything, three when one does, four when
both — rather than leaving an empty trailing line. It's called from the tail of
`bin/tmux-branch-pr` and `bin/tmux-repo-pr` (so it re-evaluates on every
window/pane switch and cache update) and from the `pane-mode-changed` hook when
leaving a mode; while a pane is in tree-mode (`prefix w`, zoomed full-screen)
the bar is hidden entirely.

The **branch-PR row** is rendered by `bin/tmux-branch-pr` (the renderer,
triggered on window/pane switches, branch change, and a background ticker) and
`bin/tmux-branch-pr-fetch` (the only thing that touches the network — a single
read-only `gh api graphql` call; GraphQL rather than `gh pr list` because the
unresolved-conversation count isn't in the REST fields, and fetching everything
in one query keeps it to one round trip). Only **open** PRs are queried — a
merged or closed PR vanishes, since this is open-work visibility, not history —
and a PR opened from a **fork** that happens to share your branch name is
skipped (only a same-repo head counts as "the PR for this branch"), so a
contributor's fork PR can't be mis-attributed to your window.
Its segments: a pluralized **commit count** (`12 commits` / `1 commit`) and diff
size (files changed, then colored `+added` (`colour2`, green) / `-deleted`
(`colour1`, red)) size up the PR at a glance; **checks** roll up `statusCheckRollup`
(GitHub's own merge of commit statuses and check runs), bucketing the
individual contexts so the numbers that matter are visible: a green `all checks
have passed`, a red `N checks failed` (with a yellow `· M pending` appended when
some are still running), or a yellow `N checks pending`. A head commit with no
checks at all shows a dim `no checks` (so "none configured" is visible rather
than silently absent), and SKIPPED runs — which the rollup state folds into a
pass — are called out as a dim `(N skipped)` alongside the green pass (or `all
checks skipped` when nothing actually ran), so an all-green row can't hide that
a check never executed. **review** shows a green `approved`, red `changes
requested`, or a dim `draft`
(a draft PR isn't up for review, so `draft` replaces the decision) — a
not-yet-reviewed PR shows nothing there; **unresolved** is a yellow count of
open review conversations, omitted at zero. Cached per repo+branch under
`~/.cache/tmux-branch-pr/`; a branch seen for the first time shows nothing (no
flashed placeholder row) until its fetch lands.

The **health row** only exists when there's something to put on it: for a
non-repo window, a repo with no remote, or one whose PR/vulnerability data isn't
readable, it's absent rather than blank. It's rendered
via `bin/tmux-repo-pr` (the renderer, triggered on window/pane switches and a
background ticker) and `bin/tmux-repo-pr-fetch` (the only thing that touches
the network — two read-only `gh api` calls, no mutating calls of any kind).
Both halves mirror
[`mission-status`](https://github.com/sueddeutsche/mission-status)'s
classification and severity color scheme, translated from raw ANSI to tmux's
native `#[fg=...]` style tags:

- **PRs** split human vs. bot (a `dependabot/`/`renovate/` branch prefix or
  matching bot login counts as bot), mirroring `IsBotPR`. The two counts are
  colored (`colour6`, cyan) only when the split is real — both sides non-zero.
  An all-human or all-bot set collapses to a plain, uncolored `(all human)` or
  `(all bot)`, since colored numbers earn their attention only when there's
  actually a split to read.
- **Vulnerabilities** are open Dependabot alerts, deduplicated by package
  (multiple CVEs on the same dependency collapse to one entry at its highest
  severity, mirroring `deduplicateAlerts`) and bucketed by severity —
  critical (`colour196`, red), high (`colour208`, orange), medium
  (`colour214`, yellow), low (`colour130`, dark yellow/brown), unknown (dim) — shown
  highest-severity-first, only non-zero buckets. Zero shows `no known
  vulnerabilities` in the footer's default text color rather than nothing, so
  you can tell the check ran — but with no emphasis, since a clean scan needs
  no action and shouldn't compete with the things that do. A repo that has
  Dependabot alerts **turned off**
  is a distinct case: it shows a yellow (`colour214`) `dependabot not
  enabled` warning instead of the green all-clear, since "off" is not the
  same as "scanned and clean" — the green would falsely imply the latter.
  (This is told apart from a plain no-access failure by the API's own
  "alerts are disabled" 403 message; no-access repos stay silent, since
  enabling alerts there isn't yours to do.)

PR listing and vulnerability-alert access are **independent GitHub
permissions** — a repo can allow one and deny the other (PRs are visible to
anyone with read access; alerts need collaborator-level access on that
specific repo) — so each half is fetched, cached, and rendered independently:
a repo shows PRs only, vulnerabilities only, both, or (most commonly, for a repo this
account isn't a collaborator on) neither, with no crash or error text either
way. Also degrades to rendering nothing if `gh` or `jq` is missing, the pane isn't
inside a git repo, the repo has no remote, or the active window belongs to a
detached session.

Requires the `gh` CLI installed and `gh auth login` run once, plus `jq` for
parsing the API responses (without it both halves silently render nothing).
Also needs tmux ≥ 3.5 for the `#{R:…}` repeat modifier the status-bar rule
above uses. Results are
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
- `npm install -g ccusage` — Claude Code token/cost tracker. `prefix u` opens monthly cost/token totals for (up to) the last six months in a floating popup; `prefix y` opens a companion popup with the aggregated per-model cost/token distribution (cost in USD — ccusage has no other currency) for this month (to date) and last month, both tables at the same column width (`bin/tmux-ccusage-popup` and `bin/tmux-ccusage-models-popup`).
- `brew install git-delta` — syntax-highlighted, line-level diffs for `git diff`/`git log`/`git show`; falls back to git's plain output if not installed.
- `brew install bat` — colorized `cat`/man-page replacement; also powers the preview pane in fzf's Ctrl-T file picker.
- [`gh`](https://cli.github.com) + `gh auth login` (and `jq`) — power the branch PR row (number, diff size, checks, review, unresolved conversations) and the per-repo open-PR and Dependabot-vulnerability counts on the status bar (see above); read-only, degrades to nothing without either.

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
