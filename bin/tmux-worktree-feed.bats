#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-worktree-feed"

GIT() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git init -q --initial-branch=main "$REPO"
  : > "$REPO/f"
  GIT add f
  GIT commit -q -m init
}

@test "prints nothing outside a git work tree" {
  run sh -c "cd '$BATS_TEST_TMPDIR' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lists the main worktree plus every linked worktree" {
  GIT worktree add -q -b feature-a "$REPO/.worktrees/feature-a"
  GIT worktree add -q -b feature-b "$REPO/.worktrees/feature-b"
  run sh -c "cd '$REPO' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "marks only the worktree matching \$PWD" {
  GIT worktree add -q -b feature-a "$REPO/.worktrees/feature-a"
  run sh -c "cd '$REPO/.worktrees/feature-a' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  marked=0
  unmarked=0
  while IFS= read -r line; do
    case "$line" in
      "* "*) marked=$((marked + 1)) ;;
      "  "*) unmarked=$((unmarked + 1)) ;;
    esac
  done <<< "$output"
  [ "$marked" -eq 1 ]
  [ "$unmarked" -eq 1 ]
}

@test "a worktree path containing a space survives the delimiter round-trip" {
  GIT worktree add -q -b feature-c "$REPO/.worktrees/feature c"
  run sh -c "cd '$REPO' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$REPO/.worktrees/feature c"* ]]
}

@test "shows the branch name stripped of refs/heads/" {
  GIT worktree add -q -b feature-a "$REPO/.worktrees/feature-a"
  run sh -c "cd '$REPO/.worktrees/feature-a' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-a"* ]]
  [[ "$output" != *"refs/heads"* ]]
}

@test "excludes a prunable worktree (directory deleted, not yet removed)" {
  GIT worktree add -q -b feature-a "$REPO/.worktrees/feature-a"
  rm -rf "$REPO/.worktrees/feature-a"
  run sh -c "cd '$REPO' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" != *"feature-a"* ]]
}

@test "excludes a bare main worktree from the list, keeps its linked worktrees" {
  bare="$BATS_TEST_TMPDIR/bare.git"
  git clone -q --bare "$REPO" "$bare"
  git -C "$bare" worktree add -q -b feature "$BATS_TEST_TMPDIR/feature-wt"
  run sh -c "cd '$BATS_TEST_TMPDIR/feature-wt' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"feature-wt"* ]]
  [[ "$output" != *"$bare"* ]]
}
