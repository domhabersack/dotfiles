# Splits inherit the current directory

## What changed

New panes and windows now open in the same directory as the pane you split from. Previously, splits always landed in `$HOME`.

**Bindings:** `prefix + |` (horizontal split), `prefix + -` (vertical split)

## Why it helps

When you're deep in a project directory and need a second pane, you no longer have to `cd` back into your working directory. The split starts exactly where you are.

## When to use it

Any time you split a pane — which is all the time. The behavior is always on, there is nothing to toggle.

## What to look out for

If you deliberately want a split to open somewhere else, you have to `cd` after the split. There is no way to override the inherited path at split time without changing the binding.
