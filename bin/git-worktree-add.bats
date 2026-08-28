#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/git-worktree-add"

GIT() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  # Canonicalize: git's own --path-format=absolute resolves symlinks (e.g.
  # macOS's /var -> /private/var), so the script's printed path always comes
  # out physical even though it never calls `pwd -P` itself. Match that here
  # so equality assertions below compare like with like.
  REPO=$(cd "$REPO" && pwd -P)
}

commit() {
  : > "$REPO/f"
  GIT add f
  GIT commit -q -m "$1"
}

@test "errors clearly with no local main and no origin/HEAD" {
  git init -q --initial-branch=trunk "$REPO"
  commit init
  run sh -c "cd '$REPO' && '$SCRIPT' feature"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no local 'main' branch"* ]]
}

@test "creates the worktree off local main and prints only its path" {
  git init -q --initial-branch=main "$REPO"
  commit init
  path=$(cd "$REPO" && "$SCRIPT" feature 2>/dev/null)
  [ "$path" = "$REPO/.worktrees/feature" ]
  [ -d "$path" ]
  GIT rev-parse --verify refs/heads/feature >/dev/null
}

@test "falls back to origin/HEAD's target branch when there is no local main" {
  git init -q --initial-branch=trunk "$REPO"
  commit init
  sha=$(GIT rev-parse HEAD)
  GIT update-ref refs/remotes/origin/trunk "$sha"
  GIT symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  # Force a genuine fallback: delete the local branch of the same name (after
  # moving off it), so only origin/trunk resolves for that name. Otherwise
  # `git worktree add ... trunk` would silently succeed by resolving the
  # coincidentally-present local branch instead of exercising the
  # origin/HEAD path this test exists to cover.
  GIT checkout -q --detach HEAD
  GIT branch -D trunk
  path=$(cd "$REPO" && "$SCRIPT" feature 2>/dev/null)
  [ "$path" = "$REPO/.worktrees/feature" ]
  [ -d "$path" ]
  GIT rev-parse --verify refs/heads/feature >/dev/null
  [ "$(GIT rev-parse feature)" = "$sha" ]
  # Guards against the exact bug this fallback used to have: passing the bare
  # name "trunk" (stripped of "origin/") let git's remote-DWIM resolve it and
  # silently create a local "trunk" tracking branch instead of "feature".
  run GIT rev-parse --verify refs/heads/trunk
  [ "$status" -ne 0 ]
}

@test "errors clearly for a repo using --separate-git-dir with no core.worktree recorded" {
  # See bin/git-worktree-root: a plain `git init --separate-git-dir=<dir>`
  # (unlike a submodule, which additionally records core.worktree) keeps no
  # reverse mapping from its gitdir back to a working directory at all --
  # nothing rules out several working directories pointing at the same
  # external gitdir. Failing loudly here is the correct, safe behavior, not
  # a bug: silently guessing would risk nesting .worktrees/ inside the
  # repo's own git metadata directory.
  gitdir="$BATS_TEST_TMPDIR/external-gitdir"
  git init -q --initial-branch=main --separate-git-dir="$gitdir" "$REPO"
  commit init
  run sh -c "cd '$REPO' && '$SCRIPT' feature"
  [ "$status" -ne 0 ]
}

@test "resolves the correct root when invoked from inside a submodule" {
  sub="$BATS_TEST_TMPDIR/sub-origin"
  git init -q --initial-branch=main "$sub"
  git -C "$sub" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty

  git init -q --initial-branch=main "$REPO"
  commit init
  GIT -c protocol.file.allow=always submodule -q add "$sub" libs/child
  GIT commit -q -m "add submodule"

  child="$REPO/libs/child"
  path=$(cd "$child" && "$SCRIPT" feature 2>/dev/null)
  [ "$path" = "$child/.worktrees/feature" ]
  [ -d "$path" ]
}

@test "resolves the same root when invoked from inside a linked worktree" {
  git init -q --initial-branch=main "$REPO"
  commit init
  first=$(cd "$REPO" && "$SCRIPT" first 2>/dev/null)
  second=$(cd "$first" && "$SCRIPT" second 2>/dev/null)
  [ "$second" = "$REPO/.worktrees/second" ]
}

@test "new branch is named exactly the given name" {
  git init -q --initial-branch=main "$REPO"
  commit init
  (cd "$REPO" && "$SCRIPT" my-feature >/dev/null 2>&1)
  GIT rev-parse --verify refs/heads/my-feature >/dev/null
}
