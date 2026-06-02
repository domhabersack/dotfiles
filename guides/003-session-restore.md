# Session restore across reboots

## What changed

Two plugins are now managed by TPM (tmux Plugin Manager): `tmux-resurrect` and `tmux-continuum`. Together they save your entire tmux state — sessions, windows, pane layout, working directories, running programs — and restore it automatically when tmux starts.

TPM itself is auto-installed on a fresh machine: if `~/.tmux/plugins/tpm` doesn't exist when tmux loads, it clones it and runs the plugin installer. You don't need to bootstrap anything manually.

**Save interval:** every 15 minutes  
**Restore on start:** automatic

**Manual save:** `prefix + Ctrl-s`  
**Manual restore:** `prefix + Ctrl-r`

## Why it helps

After a reboot — or after your laptop battery dies — you get back exactly where you were. Long-running sessions with specific layouts you've arranged by hand don't have to be rebuilt. This is especially useful when you have several projects open in different windows.

## When to use it

It's always running in the background. You benefit from it the moment you reboot and open a terminal.

## What to look out for

- **Running processes are not restored** — the layout is restored, but things like `npm run dev` or a `tail -f` will not be restarted. You need to re-run those manually.
- **The first save happens 15 minutes after tmux starts**, not immediately. If you reboot right after opening tmux on a fresh machine, there may be nothing to restore yet.
- **TPM plugins run after the `run '...tpm'` line**, which must remain the last line in `tmux.conf`. Moving anything below it can break plugin initialization.
- On a machine without internet access, the auto-install clone will fail silently and plugins simply won't load.
