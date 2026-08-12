#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-pinned-restore"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.tmux/resurrect" "$MOCK_DIR/bin"

  # Mock tmux: replays canned list-windows output and records every
  # set-window-option call into $MOCK_DIR/captured.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  list-windows)       cat "$MOCK_DIR/windows" ;;
  set-window-option)  printf 'SET\t%s\t%s\t%s\n' "$3" "$4" "$5" >> "$MOCK_DIR/captured" ;;
  *) : ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  : > "$MOCK_DIR/windows"
  : > "$MOCK_DIR/captured"

  PATH="$MOCK_DIR/bin:$PATH"
  STATE="$HOME/.tmux/resurrect/pinned"
}

# add_window <session> <window-name> <window-id>
add_window() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MOCK_DIR/windows"
}

# saved <session> <window-name>
saved() {
  printf '%s\t%s\n' "$1" "$2" >> "$STATE"
}

# the window ids that were pinned, in order
pinned_ids() { cut -f2 "$MOCK_DIR/captured" | tr '\n' ' ' | sed 's/ $//'; }

@test "pins exactly the windows named in the state file" {
  add_window work notes '@1'
  add_window work code  '@2'
  add_window play games '@3'
  saved work notes
  saved play games
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pinned_ids)" = "@1 @3" ]
}

@test "sets @pinned to 1" {
  add_window work notes '@1'
  saved work notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/captured")" = "$(printf 'SET\t@1\t@pinned\t1')" ]
}

@test "matches on session and name together, not name alone" {
  add_window work notes '@1'
  add_window play notes '@2'
  saved play notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pinned_ids)" = "@2" ]
}

@test "matches window names containing spaces" {
  add_window work "my long name" '@7'
  saved work "my long name"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pinned_ids)" = "@7" ]
}

@test "is additive: windows absent from the file are left untouched" {
  add_window work notes '@1'
  add_window work code  '@2'
  saved work notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pinned_ids)" = "@1" ]
}

@test "exits quietly when no state file exists" {
  add_window work notes '@1'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/captured" ]
}

@test "exits quietly when the state file is empty" {
  add_window work notes '@1'
  : > "$STATE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_DIR/captured" ]
}

@test "ignores saved windows that no longer exist" {
  add_window work notes '@1'
  saved work notes
  saved work "long gone"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pinned_ids)" = "@1" ]
}

@test "pins every window sharing a name within a session (documented blind spot)" {
  add_window work notes '@1'
  add_window work notes '@2'
  saved work notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(pinned_ids)" = "@1 @2" ]
}
