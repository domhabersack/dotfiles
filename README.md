# Dominik Habersack's Dot Files

Customizations of several command-line utilities.

## Setup

Clone this repository to `~/.dotfiles`:

```sh
git clone <repo-url> ~/.dotfiles
```

Symlink each dotfile from your home directory:

```sh
ln -s ~/.dotfiles/gitconfig ~/.gitconfig
ln -s ~/.dotfiles/gitignore_global ~/.gitignore_global
ln -s ~/.dotfiles/sqliterc ~/.sqliterc
ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/vimrc ~/.vimrc
ln -s ~/.dotfiles/zshrc ~/.zshrc
```

### Machine-specific settings

Each dotfile sources a `.local` counterpart that is not committed to this repository. Create these files on each machine for settings that should not be shared (paths with usernames, credentials, machine-specific tools):

| File | Purpose |
|------|---------|
| `~/.gitconfig.local` | name, email, signing keys, machine-specific credentials |
| `~/.tmux.conf.local` | local tmux overrides |
| `~/.vimrc.local` | local vim settings |
| `~/.zshrc.local` | machine-specific paths, environment variables, aliases |

Example `~/.gitconfig.local`:

```ini
[user]
  name = Dom Habersack
  email = dom@example.com
```

Example `~/.zshrc.local`:

```sh
export PATH="/Users/yourusername/.local/bin:/Users/yourusername/homebrew/bin:$PATH"
```

## Contents

* gitconfig - aliases, colors
* tmux.conf - remapped prefix, simple status bar, clear pane-highlighting
* vimrc - syntax highlighting, line numbers, coloring, gutter, soft tabs
* zshrc - aliases, colors, functions, sexy prompt

## Highlights

Some of the most useful elements of these dotfiles are:

- `git llog` (or `gl`) for a lovely git log
- `md DIRECTORY` to create a directory and change to it
- git- and rbenv-information in prompt

## Screenshots

### zsh prompt

![zsp prompt](/assets/images/zsh-prompt.png)

### Lovely git log (`git llog`/`gl`)

![git llog](/assets/images/git-llog.png)
