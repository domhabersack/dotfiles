# Session restore across reboots

## What changed

Two plugins are now managed by TPM (tmux Plugin Manager): `tmux-resurrect` and `tmux-continuum`. Together they save your entire tmux state — sessions, windows, pane layout, working directories, running programs — but restoring it is always something you ask for, never something that happens on its own.

TPM itself is auto-installed on a fresh machine: if `~/.tmux/plugins/tpm` doesn't exist when tmux loads, it clones it and runs the plugin installer. You don't need to bootstrap anything manually.

**Save interval:** every 15 minutes  
**Restore on start:** never automatic — restoring is always an explicit `prefix + Ctrl-r`

**Manual save:** `prefix + Ctrl-s`  
**Manual restore:** `prefix + Ctrl-r`

## Why it helps

After a reboot — or after your laptop battery dies — you can get back exactly where you were, on request. Long-running sessions with specific layouts you've arranged by hand don't have to be rebuilt. This is especially useful when you have several projects open in different windows.

## When to use it

Saving always runs in the background, but restoring is something you trigger yourself with `prefix + Ctrl-r` — for example right after a reboot, before creating any new sessions by hand. It's deliberately not automatic: an automatic restore used to fire on the very first `tmux new-session`, which meant a plain `tmux new-session -s NAME` would silently reincarnate the last saved state instead of creating the session you asked for.

## What to look out for

- **Running processes are not restored** — the layout is restored, but things like `npm run dev` or a `tail -f` will not be restarted. You need to re-run those manually.
- **The first save happens 15 minutes after tmux starts**, not immediately. If you reboot right after opening tmux on a fresh machine, there may be nothing to restore yet.
- **TPM plugins run after the `run '...tpm'` line**, which must remain the last line in `tmux.conf`. Moving anything below it can break plugin initialization.
- On a machine without internet access, the auto-install clone will fail silently and plugins simply won't load.
