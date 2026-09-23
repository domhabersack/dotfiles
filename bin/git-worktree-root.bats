#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/git-worktree-root"

GIT() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  # Canonicalize: the script's output always comes out physical (it's built
  # from git's own --path-format=absolute), so equality assertions below need
  # $REPO in that same form -- e.g. macOS's /var -> /private/var.
  REPO=$(cd "$REPO" && pwd -P)
  git init -q --initial-branch=main "$REPO"
  : > "$REPO/f"
  GIT add f
  GIT commit -q -m init
}

@test "resolves the main worktree's own root" {
  [ "$("$SCRIPT" "$REPO")" = "$REPO" ]
}

@test "resolves the same root from inside a linked worktree" {
  GIT worktree add -q -b feature "$REPO/.worktrees/feature"
  [ "$("$SCRIPT" "$REPO/.worktrees/feature")" = "$REPO" ]
}

@test "resolves a submodule's own root, not the superproject's, from the submodule root" {
  sub="$BATS_TEST_TMPDIR/sub-origin"
  git init -q --initial-branch=main "$sub"
  git -C "$sub" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty
  GIT -c protocol.file.allow=always submodule -q add "$sub" libs/child
  GIT commit -q -m "add submodule"
  child="$REPO/libs/child"
  [ "$("$SCRIPT" "$child")" = "$child" ]
}

@test "resolves a submodule's own root from inside the submodule's own linked worktree" {
  sub="$BATS_TEST_TMPDIR/sub-origin"
  git init -q --initial-branch=main "$sub"
  git -C "$sub" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty
  GIT -c protocol.file.allow=always submodule -q add "$sub" libs/child
  GIT commit -q -m "add submodule"
  child="$REPO/libs/child"
  git -C "$child" worktree add -q -b feature "$child/.worktrees/feature"
  [ "$("$SCRIPT" "$child/.worktrees/feature")" = "$child" ]
}

@test "fails loudly for a repository relocated via --separate-git-dir with no reverse mapping" {
  gitdir="$BATS_TEST_TMPDIR/external-gitdir"
  REPO2="$BATS_TEST_TMPDIR/repo2"
  git init -q --initial-branch=main --separate-git-dir="$gitdir" "$REPO2"
  git -C "$REPO2" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty
  run "$SCRIPT" "$REPO2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not resolve"* ]]
}

@test "fails loudly for a bare repository with no working tree of its own" {
  bare="$BATS_TEST_TMPDIR/bare.git"
  git init -q --bare --initial-branch=main "$bare"
  run "$SCRIPT" "$bare"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not resolve"* ]]
}
