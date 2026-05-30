# Clipboard integration in copy mode

## What changed

In tmux copy mode, pressing `y` now pipes the selection directly to `pbcopy`, putting it on the macOS clipboard. Previously, `y` only copied to tmux's internal paste buffer — you couldn't paste into other apps.

**Key sequence:** `prefix + Escape` to enter copy mode, `v` to begin selection, `y` to copy.

## Why it helps

You can copy text from a terminal pane — a file path, a URL, a stack trace — and paste it anywhere on your Mac with `Cmd + V`. The workflow matches what you'd expect from selecting text normally.

## When to use it

- Copying a command output you want to share somewhere
- Grabbing a file path to paste into Finder or a browser
- Copying a long URL printed by a command

## What to look out for

`pbcopy` is macOS-only. On a Linux machine this binding will fail silently — the copy will appear to succeed but the clipboard won't be populated. If you SSH into Linux boxes and need this to work there, you would need `xclip` or `xsel` and a conditional in the config.
