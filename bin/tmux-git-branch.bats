#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped state is how @test isolates each case

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-git-branch"

# A throwaway git repo per test, with identity passed inline so the suite never
# depends on (or mutates) the runner's global git config.
GIT() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
}

commit() {
  : > "$REPO/f"
  GIT add f
  GIT commit -q -m "$1"
}

@test "prints nothing outside a git work tree" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prints the current branch in parentheses" {
  git init -q "$REPO"
  commit init
  GIT checkout -q -b feature/login
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "(feature/login)" ]
}

@test "falls back to the short hash on a detached HEAD" {
  git init -q "$REPO"
  commit init
  GIT checkout -q --detach HEAD
  sha=$(GIT rev-parse --short HEAD)
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "($sha)" ]
}

@test "shows the unborn branch in a repo with no commits yet" {
  git init -q "$REPO"
  # Pin the initial branch so the assertion doesn't depend on the runner's
  # init.defaultBranch (master vs main); HEAD resolves even with no commits.
  GIT symbolic-ref HEAD refs/heads/main
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "(main)" ]
}

@test "defaults to the current directory when given no argument" {
  git init -q "$REPO"
  commit init
  GIT checkout -q -b topic
  run sh -c "cd '$REPO' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$output" = "(topic)" ]
}
