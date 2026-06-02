# Smarter shell history

## What changed

History is now shared across all open shells in real time, grown from 10,000 to 100,000 entries, and enriched with timestamps. Several options were added to control duplicate handling, whitespace, and `!`-expansion safety.

### Key options

| Option | Effect |
|---|---|
| `SHARE_HISTORY` | All open shells and tmux panes pull from the same history as you type |
| `INC_APPEND_HISTORY` | Each command is written immediately, not when the shell exits |
| `HIST_IGNORE_ALL_DUPS` | Running the same command again removes the older occurrence |
| `HIST_IGNORE_SPACE` | Prefix a command with a space to keep it out of history entirely |
| `HIST_VERIFY` | `!!` and `!foo` expansions show the expanded command before running it |
| `EXTENDED_HISTORY` | Each entry records a Unix timestamp (useful for forensics) |

## Why it helps

Without `SHARE_HISTORY`, each tmux pane has its own history silo. A command you ran in pane 2 isn't findable when you `Ctrl-R` in pane 3. With sharing enabled, all panes draw from the same pool immediately.

`HIST_IGNORE_SPACE` is useful for commands you run once and don't want cluttering search — credentials passed on the command line, throwaway one-liners, etc.

## When to use it

`SHARE_HISTORY` is always on. `HIST_IGNORE_SPACE` is opt-in per command: just type a space before the command.

## What to look out for

- `SHARE_HISTORY` and `HIST_IGNORE_ALL_DUPS` interact: if you run a command in one pane repeatedly, other panes will see it appear, then disappear as the duplicate is removed. This is harmless but can look odd.
- Very large history files (`~/.zsh_history` at 100k entries) grow slowly over time but are still small in practice — a few megabytes at most.
- `HIST_VERIFY` adds a confirmation step for `!`-expansion. If you use `!!` to re-run the last command as root (`sudo !!`), you'll see the expanded form first. Press Enter to confirm.
