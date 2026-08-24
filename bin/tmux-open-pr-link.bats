#!/usr/bin/env bats
# shellcheck disable=SC2016  # bats: literal backticks/dollars in fixtures need no expansion

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-open-pr-link"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.cache/tmux-branch-pr" "$MOCK_DIR/bin"

  # Mock tmux: `display-message -p '#{pane_current_path}'` returns whatever
  # path this test points PANE_PATH at, standing in for "the active pane".
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  display-message) printf '%s\n' "$PANE_PATH" ;;
  *) : ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"

  # Mock open: records the URL it was asked to open instead of launching a
  # real browser — the only way to observe what the script decided to do.
  cat > "$MOCK_DIR/bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$MOCK_DIR/opened"
EOF
  chmod +x "$MOCK_DIR/bin/open"
  : > "$MOCK_DIR/opened"

  PATH="$MOCK_DIR/bin:$PATH"
}

# make_repo <path> [branch] — inits a repo with a GitHub origin, optionally on
# a named branch (works before any commit: HEAD is a symbolic ref either way).
make_repo() {
  git init -q "$1"
  git -C "$1" remote add origin https://github.com/example-owner/example-repo.git
  [ -z "${2:-}" ] || git -C "$1" checkout -q -b "$2"
}

write_branch_pr_cache() {
  # write_branch_pr_cache <repo> <branch> <json>
  safe=$(printf '%s' "$1/$2" | tr '/' '_')
  printf '%s' "$3" > "$HOME/.cache/tmux-branch-pr/$safe.json"
}

@test "does nothing when called with no range argument" {
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}

@test "does nothing for a range it doesn't recognize" {
  make_repo "$BATS_TEST_TMPDIR/repo"
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT" bogus
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}

@test "repo_pr opens the repo's pull-requests listing page" {
  make_repo "$BATS_TEST_TMPDIR/repo"
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT" repo_pr
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/opened")" = "https://github.com/example-owner/example-repo/pulls" ]
}

@test "repo_pr does nothing when the path isn't inside a git repo" {
  mkdir -p "$BATS_TEST_TMPDIR/plain-dir"
  PANE_PATH="$BATS_TEST_TMPDIR/plain-dir" run "$SCRIPT" repo_pr
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}

@test "repo_pr does nothing when the repo has no origin remote" {
  git init -q "$BATS_TEST_TMPDIR/no-origin"
  PANE_PATH="$BATS_TEST_TMPDIR/no-origin" run "$SCRIPT" repo_pr
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}

@test "branch_pr opens the specific PR from the cached number" {
  make_repo "$BATS_TEST_TMPDIR/repo" feat/foo
  write_branch_pr_cache example-owner/example-repo feat/foo '{"status":"ok","has":true,"number":42}'
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT" branch_pr
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/opened")" = "https://github.com/example-owner/example-repo/pull/42" ]
}

@test "branch_pr does nothing when no cache exists for the branch" {
  make_repo "$BATS_TEST_TMPDIR/repo" feat/foo
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT" branch_pr
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}

@test "branch_pr does nothing when the cache has no open PR" {
  make_repo "$BATS_TEST_TMPDIR/repo" feat/foo
  write_branch_pr_cache example-owner/example-repo feat/foo '{"status":"ok","has":false}'
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT" branch_pr
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}

@test "branch_pr does nothing on a detached HEAD" {
  make_repo "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" commit -q --allow-empty -m init
  rev=$(git -C "$BATS_TEST_TMPDIR/repo" rev-parse HEAD)
  git -C "$BATS_TEST_TMPDIR/repo" checkout -q "$rev"
  PANE_PATH="$BATS_TEST_TMPDIR/repo" run "$SCRIPT" branch_pr
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/opened" ]
}
