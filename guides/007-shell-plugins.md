# Shell plugins: autosuggestions, syntax highlighting, and zoxide

## What changed

Three plugins are now auto-installed on first shell start:

- **zsh-autosuggestions** — suggests completions from history as you type, shown in gray
- **zsh-syntax-highlighting** — colors commands as you type: green for valid, red for unknown
- **zoxide** — a smarter `cd` that learns which directories you visit most

### zsh-autosuggestions

Accept the gray suggestion with the right arrow key (`→`) or `Ctrl-E`. Continue typing to ignore it. The suggestion strategy tries history first, then zsh completion.

### zsh-syntax-highlighting

No interaction needed — colors appear automatically as you type.

### zoxide

`z` replaces `cd` for directories you've visited before.

| Command | Effect |
|---|---|
| `z foo` | Jump to the highest-frecency directory matching `foo` |
| `z foo bar` | Narrow by multiple terms |
| `zi foo` | Interactive picker (uses fzf) |
| `cd` | Still works exactly as before |

Zoxide must be installed separately — it's not auto-cloned like the zsh plugins. Install with `brew install zoxide`. If it isn't installed, the `eval "$(zoxide init zsh)"` line no-ops silently.

## Why it helps

**Autosuggestions** saves keystrokes on commands you run frequently. Long `git` commands, `docker` invocations, `npm run` scripts — once they're in history, you often only need to type the first few characters.

**Syntax highlighting** catches typos before you press Enter. A command that appears red means zsh doesn't recognize it — you can fix it before running it, rather than reading an error after.

**Zoxide** removes the friction of `cd`-ing to deeply nested project directories. Instead of `cd ~/code/clients/acme/api/src`, you type `z acme` after you've been there once.

## When to use it

- Autosuggestions and syntax highlighting are always on — there's nothing to invoke
- Use `z` anywhere you'd use `cd` for a directory you've visited before
- `zi` is useful when multiple directories match the same term

## What to look out for

- **Syntax highlighting must be sourced last** in `.zshrc` — it wraps zle widgets, and other plugins loaded after it can conflict. The load order in the config is intentional.
- **Autosuggestions slows down very large histories** — at 100k entries (the new limit), it's still fast, but on an older machine you might notice a slight lag on each keystroke.
- **Zoxide builds its database from your actual `cd` history**, so it won't know about directories you haven't visited since installing it. `z` becomes more useful over days of normal use.
- The zsh plugins auto-clone from GitHub on first start. On a machine without internet access they'll be missing until you clone them manually into `~/.zsh/plugins/`.
