#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-worktree-status"

GIT() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git init -q --initial-branch=main "$REPO"
  : > "$REPO/f"
  GIT add f
  GIT commit -q -m init
}

here_of() { "$SCRIPT" "$1" | sed -n '1p'; }
pending_of() { "$SCRIPT" "$1" | sed -n '2p'; }

@test "prints two empty lines outside a git work tree" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\n')" ]
}

@test "marks a linked worktree with the fork glyph, no pending marker" {
  GIT worktree add -q -b feature "$REPO/.worktrees/feature"
  [ "$(here_of "$REPO/.worktrees/feature")" = "⎇" ]
  [ -z "$(pending_of "$REPO/.worktrees/feature")" ]
}

@test "marks the main worktree with a pending count when linked worktrees exist" {
  GIT worktree add -q -b feature-a "$REPO/.worktrees/feature-a"
  GIT worktree add -q -b feature-b "$REPO/.worktrees/feature-b"
  [ -z "$(here_of "$REPO")" ]
  [ "$(pending_of "$REPO")" = "⎇2" ]
}

@test "shows no pending marker on the main worktree when no linked worktrees exist" {
  [ -z "$(here_of "$REPO")" ]
  [ -z "$(pending_of "$REPO")" ]
}

@test "a prunable worktree (directory deleted, not yet removed) still counts toward pending" {
  GIT worktree add -q -b feature "$REPO/.worktrees/feature"
  rm -rf "$REPO/.worktrees/feature"
  [ "$(pending_of "$REPO")" = "⎇1" ]
}

@test "resolves correctly for a submodule (gitdir relocated, but core.worktree recorded)" {
  sub="$BATS_TEST_TMPDIR/sub-origin"
  git init -q --initial-branch=main "$sub"
  git -C "$sub" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty
  GIT -c protocol.file.allow=always submodule -q add "$sub" libs/child
  GIT commit -q -m "add submodule"
  child="$REPO/libs/child"
  git -C "$child" worktree add -q -b feature "$child/.worktrees/feature"
  [ -z "$(here_of "$child")" ]
  [ "$(pending_of "$child")" = "⎇1" ]
  [ "$(here_of "$child/.worktrees/feature")" = "⎇" ]
}

@test "degrades safely (mislabels rather than errors) for --separate-git-dir with no core.worktree" {
  # git-worktree-root fails outright for this shape (see its own bats suite)
  # since git keeps no reverse mapping from a plain --separate-git-dir gitdir
  # back to a working directory -- nothing rules out several working
  # directories pointing at the same external gitdir. This script treats
  # that failure as "not resolvably the main worktree", so it mislabels the
  # main worktree here as if it were linked (⎇) instead of showing a pending
  # count -- documented as a known, narrow limitation, not a crash.
  gitdir="$BATS_TEST_TMPDIR/external-gitdir"
  REPO2="$BATS_TEST_TMPDIR/repo2"
  git init -q --initial-branch=main --separate-git-dir="$gitdir" "$REPO2"
  git -C "$REPO2" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty
  run "$SCRIPT" "$REPO2"
  [ "$status" -eq 0 ]
  [ "$(here_of "$REPO2")" = "⎇" ]
}
