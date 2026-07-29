# git-delta: syntax-highlighted diffs

## What changed

`git diff`, `git log -p`, `git show`, and `git add -p` now render through [delta](https://github.com/dandavison/delta) instead of git's plain output.

```ini
[core]
  pager = delta
[interactive]
  diffFilter = delta --color-only
[delta]
  navigate = true
```

Delta isn't bundled — install it with `brew install git-delta`. If it isn't installed, git quietly falls back to its normal unpaged output; nothing breaks.

## Why it helps

Delta highlights diffs at the word/character level within a changed line, not just whole lines in red/green, so a one-word edit in a long line is obvious instead of buried in a wall of red-then-green. `navigate = true` lets you jump between files in a multi-file diff with `n`/`N` instead of scrolling.

## When to use it

Anywhere you'd already run `git diff`, `git log -p`, `git show`, or stage hunks interactively with `git add -p` — no new commands to learn, the pager is just better.

## What to look out for

- Optional install (`brew install git-delta`). Since git falls back silently when the pager binary is missing, there's no error to tell you it's inactive — if diffs still look like plain git output, check `delta --version`.
- `diffFilter = delta --color-only` is what makes `git add -p`'s hunk view colorized too; without it only `diff`/`log`/`show` would pick up delta.
- Delta reads its own config from `[delta]` in `gitconfig`; further tuning (side-by-side view, line numbers, themes) goes there.
