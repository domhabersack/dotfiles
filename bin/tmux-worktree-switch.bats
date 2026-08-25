#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-worktree-switch"

GIT() { git -C "$ROOT" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

setup() {
  MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: logs every invocation (one line per call, space-joined argv) to
  # $MOCK_LOG, and answers just enough of the real commands to drive the
  # script's own branching -- list-windows/display-message read from a small
  # fixture file ("<window_id> <session> <path>" per line) the test writes;
  # select-window/switch-client/new-window are pure side effects here, so
  # they only need to be logged, not actually acted on. `git` itself is NOT
  # mocked -- the script now resolves each window's real worktree root via a
  # live `git rev-parse --show-toplevel`, so every fixture path must be a
  # real, on-disk git worktree for that resolution to succeed.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$1" in
  list-windows)
    awk '{print $1, $3}' "$MOCK_WINDOWS"
    ;;
  display-message)
    if [ "$3" = "-t" ]; then
      id=$4
      awk -v id="$id" '$1 == id { print $2 }' "$MOCK_WINDOWS"
    else
      printf '%s\n' "$CURRENT_SESSION"
    fi
    ;;
  new-window)
    printf '%s\n' "$NEW_WINDOW_ID"
    ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"

  MOCK_LOG="$BATS_TEST_TMPDIR/tmux.log"
  MOCK_WINDOWS="$BATS_TEST_TMPDIR/windows"
  : > "$MOCK_LOG"
  : > "$MOCK_WINDOWS"
  CURRENT_SESSION=mysess
  NEW_WINDOW_ID=@99
  export MOCK_LOG MOCK_WINDOWS CURRENT_SESSION NEW_WINDOW_ID
  export PATH="$MOCK_DIR/bin:$PATH"

  ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$ROOT"
  # Canonicalize: the script resolves every path through git (which always
  # comes out physical), so fixture/assertion paths need to match that form
  # too -- e.g. macOS's /var -> /private/var.
  ROOT=$(cd "$ROOT" && pwd -P)
  git init -q --initial-branch=main "$ROOT"
  : > "$ROOT/f"
  GIT add f
  GIT commit -q -m init
}

# add_window <id> <session> <path>
add_window() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" | tr '\t' ' ' >> "$MOCK_WINDOWS"
}

@test "selects an existing window already in the current session" {
  add_window @1 mysess "$ROOT"
  run "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"select-window -t @1"* ]]
  [[ "$(cat "$MOCK_LOG")" != *"new-window"* ]]
  [[ "$(cat "$MOCK_LOG")" != *"switch-client"* ]]
}

@test "switches session before selecting a match in a different session" {
  add_window @2 othersess "$ROOT"
  run "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
  switch_line=$(grep -n "switch-client -t othersess" "$MOCK_LOG" | cut -d: -f1)
  select_line=$(grep -n "select-window -t @2" "$MOCK_LOG" | cut -d: -f1)
  [ -n "$switch_line" ]
  [ -n "$select_line" ]
  [ "$switch_line" -lt "$select_line" ]
}

@test "matches a window whose pane has since cd'd into a subdirectory of the target worktree" {
  GIT worktree add -q -b feature "$ROOT/.worktrees/feature"
  mkdir -p "$ROOT/.worktrees/feature/src/lib"
  add_window @3 mysess "$ROOT/.worktrees/feature/src/lib"
  run "$SCRIPT" "$ROOT/.worktrees/feature"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"select-window -t @3"* ]]
  [[ "$(cat "$MOCK_LOG")" != *"new-window"* ]]
}

@test "creates a new window named plainly after the repo for a linked worktree with no existing match" {
  GIT worktree add -q -b feature "$ROOT/.worktrees/feature"
  repo_name=$(basename "$ROOT")
  run "$SCRIPT" "$ROOT/.worktrees/feature"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"new-window -t mysess: -c $ROOT/.worktrees/feature -n $repo_name -P -F #{window_id}"* ]]
  [[ "$(cat "$MOCK_LOG")" == *"select-window -t @99"* ]]
}

@test "creates a new window named plainly after the repo for the main worktree with no existing match" {
  repo_name=$(basename "$ROOT")
  run "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"new-window -t mysess: -c $ROOT -n $repo_name -P -F #{window_id}"* ]]
}

@test "names a submodule's own worktree window after the submodule, not the superproject" {
  sub="$BATS_TEST_TMPDIR/sub-origin"
  git init -q --initial-branch=main "$sub"
  git -C "$sub" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init --allow-empty
  GIT -c protocol.file.allow=always submodule -q add "$sub" libs/child
  GIT commit -q -m "add submodule"
  child="$ROOT/libs/child"
  run "$SCRIPT" "$child"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"new-window -t mysess: -c $child -n child -P -F #{window_id}"* ]]
}

@test "a trailing slash on the input still matches an already-open window" {
  add_window @1 mysess "$ROOT"
  run "$SCRIPT" "$ROOT/"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"select-window -t @1"* ]]
}
