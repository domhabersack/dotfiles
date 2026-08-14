#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped state is how @test isolates each case

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-local-diff"

# A throwaway git repo per test, with identity passed inline so the suite never
# depends on (or mutates) the runner's global git config.
GIT() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
}

# A repo whose trunk is $1 (default main) with one committed file, sitting on a
# feature branch — the shape almost every case below starts from.
init_repo() {
  git init -q "$REPO"
  GIT symbolic-ref HEAD "refs/heads/${1:-main}"
  printf 'base\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m init
}

# The counts without the tmux style tags, so assertions read as the user sees
# them: "4 files · +120 -30".
plain() { printf '%s' "$1" | sed -e 's/#\[[^]]*\]//g'; }

@test "prints nothing outside a git work tree" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prints nothing on a clean checkout of the trunk" {
  init_repo
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prints nothing when the repo has no local trunk ref" {
  git init -q "$REPO"
  GIT symbolic-ref HEAD refs/heads/experiment
  printf 'base\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m init
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "counts committed work on a feature branch" {
  init_repo
  GIT checkout -q -b feature
  printf 'base\nadded\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m work
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
}

@test "counts staged and unstaged work alongside commits" {
  init_repo
  GIT checkout -q -b feature
  printf 'committed\n' > "$REPO/committed"
  GIT add committed
  GIT commit -q -m work
  printf 'staged\n' > "$REPO/staged"
  GIT add staged
  printf 'base\nunstaged\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "3 files · +3 -0" ]
}

@test "counts uncommitted work while sitting on the trunk itself" {
  init_repo
  printf 'base\nmore\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
}

@test "counts deletions" {
  init_repo
  GIT checkout -q -b feature
  GIT rm -q tracked
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +0 -1" ]
}

@test "counts untracked files as pure additions" {
  init_repo
  printf 'one\ntwo\nthree\n' > "$REPO/new"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +3 -0" ]
}

@test "counts an untracked file whose last line has no trailing newline" {
  init_repo
  printf 'one\ntwo' > "$REPO/new"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +2 -0" ]
}

@test "counts untracked files whose names contain spaces" {
  init_repo
  printf 'one\ntwo\n' > "$REPO/two words.txt"
  printf 'three\n' > "$REPO/another one.txt"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "2 files · +3 -0" ]
}

@test "ignores untracked files excluded by .gitignore" {
  init_repo
  printf 'build/\n' > "$REPO/.gitignore"
  GIT add .gitignore
  GIT commit -q -m ignore
  mkdir -p "$REPO/build"
  printf 'junk\n' > "$REPO/build/out"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "counts untracked files outside the directory it is given" {
  init_repo
  mkdir -p "$REPO/sub"
  printf 'in-sub\n' > "$REPO/sub/keep"
  printf 'at-root\n' > "$REPO/at-root"
  run "$SCRIPT" "$REPO/sub"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "2 files · +2 -0" ]
}

@test "compares against the trunk ref itself, not the merge base" {
  init_repo
  GIT checkout -q -b feature
  printf 'base\nfeature\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m feature-work
  # main moves ahead with a line the branch doesn't have: a merge-base diff
  # would ignore it, a trunk-tip diff reports it as a deletion.
  GIT checkout -q main
  printf 'base\nmain-only\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m main-work
  GIT checkout -q feature
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -1" ]
}

@test "shrinks back to the branch's own work after a rebase onto main" {
  init_repo
  GIT checkout -q -b feature
  printf 'feature\n' > "$REPO/feature-file"
  GIT add feature-file
  GIT commit -q -m feature-work
  GIT checkout -q main
  printf 'base\nmain-only\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m main-work
  GIT checkout -q feature
  before=$(plain "$("$SCRIPT" "$REPO")")
  [ "$before" = "2 files · +1 -1" ]
  GIT rebase -q main
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
}

@test "counts a binary file as changed without counting lines" {
  init_repo
  printf '\000\001\002\n' > "$REPO/blob.bin"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  # Untracked, so it goes through the line count rather than numstat's "-".
  GIT add blob.bin
  GIT commit -q -m blob
  printf '\000\003\004\005\n' > "$REPO/blob.bin"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +0 -0" ]
}

@test "falls back to master when there is no main" {
  init_repo master
  GIT checkout -q -b feature
  printf 'base\nadded\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
}

@test "prefers main over master when both exist" {
  init_repo
  GIT branch master
  GIT checkout -q -b feature
  # Move master away so a master-based comparison would give a different count.
  printf 'base\nmaster-only\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m master-work
  GIT branch -f master feature
  printf 'base\nmaster-only\nmore\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  # vs main: two added lines. vs master: one.
  [ "$(plain "$output")" = "1 file · +2 -0" ]
}

@test "ignores a remote-tracking main with no local branch" {
  git init -q "$REPO"
  GIT symbolic-ref HEAD refs/heads/experiment
  printf 'base\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m init
  GIT update-ref refs/remotes/origin/main HEAD
  printf 'base\nchanged\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "emits green and red style tags around the counts" {
  init_repo
  printf 'base\nadded\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = '1 file · #[fg=colour2]+1#[default] #[fg=colour1]-0#[default]' ]
}

@test "output carries no literal # that would need escaping on re-expansion" {
  init_repo
  printf 'base\nadded\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$(plain "$output" | tr -dc '#')" ]
}

@test "defaults to the current directory when given no argument" {
  init_repo
  printf 'base\nadded\n' > "$REPO/tracked"
  run env -C "$REPO" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
}

@test "pluralises the file count" {
  init_repo
  printf 'one\n' > "$REPO/a"
  printf 'two\n' > "$REPO/b"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "2 files · +2 -0" ]
}
