# shellcheck CI for bin/ scripts

## What changed

A GitHub Actions workflow (`.github/workflows/shellcheck.yml`) now runs `shellcheck -x` over every script in `bin/` on any push or pull request that touches that directory. The handful of pre-existing info-level findings were resolved with targeted `# shellcheck disable=...` comments rather than silenced blindly — each one explains why the flagged pattern (intentional word-splitting, a single-quoted variable meant to expand in a child shell, a function invoked only via a trap) is correct as written.

## Why it helps

The `bin/` scripts drive tmux hooks that fire silently in the background (window coloring, sorting, freshness, Claude Code notifications). A quoting mistake or typo in one of these doesn't throw a visible error — it just quietly stops working, or works most of the time and breaks on an edge case. Catching that at CI time, before it merges, is a lot cheaper than noticing "windows stopped coloring" days later.

## When to use it

Automatic — it runs on every push/PR touching `bin/**`. To check locally before pushing, match what CI runs:

```sh
cd bin && shellcheck -x *
```

## What to look out for

- The `# shellcheck source=./tmux-locklib` directives (used so shellcheck lints the shared lock library inline with its callers) resolve relative to the **working directory**, not the linted file's location. Running `shellcheck -x bin/*` from the repo root re-surfaces "not following" notices for that reason — always `cd bin` first, as the workflow does.
- Shellcheck's finding codes for the same underlying issue can differ by version: the trap-invoked `release()` function was flagged as `SC2329` locally (shellcheck 0.11.0) but `SC2317` on the GitHub Actions runner. If a currently-annotated line starts failing under a new code, add that code to the existing disable comment rather than assuming it's a new bug.
- If you add a new script to `bin/`, it's picked up automatically (the workflow globs `*`) — no need to register it anywhere.
