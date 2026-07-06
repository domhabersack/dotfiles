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
brew install neovim ripgrep fd
mkdir -p ~/.config/nvim
ln -s ~/.dotfiles/vimrc ~/.config/nvim/init.vim
```

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

### Plugins (auto-installed)

On first shell/editor start, plugins install themselves automatically:

- **fzf** + **zsh-autosuggestions** + **zsh-syntax-highlighting** — cloned by `zshrc` on first shell start (same pattern as TPM in `tmux.conf`).
- **vim-plug** — bootstrapped by `vimrc` on first `nvim` launch; all plugins install automatically.
- **Language servers** (tsserver, tailwindcss, eslint, cssls, html, jsonls) — installed by mason on the second `nvim` launch.

### Optional tools

- `brew install zoxide` — smart `cd` with frecency; auto-activated if present.

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
