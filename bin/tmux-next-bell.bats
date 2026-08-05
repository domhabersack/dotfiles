#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-next-bell"

setup() {
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: reports the current session/window from files this test writes,
  # serves canned list-windows output, records select-window / display-message
  # calls into $MOCK_DIR/captured. Only shell builtins, so it needs no external
  # tools on PATH.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  display-message)
    # `-p <fmt>` prints current context; without -p it's a user-facing message.
    if [ "$2" = "-p" ]; then
      case "$3" in
        '#{session_name}')  cat "$MOCK_DIR/cur_session" ;;
        '#{window_index}')  cat "$MOCK_DIR/cur_index" ;;
      esac
    else
      printf 'MSG\t%s\n' "$2" >> "$MOCK_DIR/captured"
    fi
    ;;
  list-windows)
    # args: list-windows -t <sess> -F <fmt>
    f="$MOCK_DIR/windows_$3"
    [ -f "$f" ] && while IFS= read -r ln; do printf '%s\n' "$ln"; done < "$f"
    ;;
  select-window)
    # args: select-window -t <sess:index>
    printf 'SELECT\t%s\n' "$3" >> "$MOCK_DIR/captured"
    ;;
  *) : ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  : > "$MOCK_DIR/captured"

  PATH="$MOCK_DIR/bin:$PATH"
}

# current <session> <window-index>
current() {
  printf '%s' "$1" > "$MOCK_DIR/cur_session"
  printf '%s' "$2" > "$MOCK_DIR/cur_index"
}

# add_window <session> <bell-flag> <window-index>
add_window() {
  printf '%s %s\n' "$2" "$3" >> "$MOCK_DIR/windows_$1"
}

# the last select-window / display-message target captured
selected() { grep '^SELECT	' "$MOCK_DIR/captured" | tail -1 | cut -f2-; }
messaged() { grep '^MSG	'    "$MOCK_DIR/captured" | tail -1 | cut -f2-; }

@test "jumps to the next bell window after the current one" {
  current work 1
  add_window work 0 1
  add_window work 1 2
  add_window work 1 4
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(selected)" = "work:2" ]
}

@test "skips a bell window at or before the current index" {
  current work 3
  add_window work 1 2
  add_window work 0 3
  add_window work 1 5
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(selected)" = "work:5" ]
}

@test "wraps to the lowest bell index when none is past the current window" {
  current work 5
  add_window work 1 1
  add_window work 1 3
  add_window work 0 5
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(selected)" = "work:1" ]
}

@test "shows a message and selects nothing when no window has a bell" {
  current work 1
  add_window work 0 1
  add_window work 0 2
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(selected)" ]
  [ "$(messaged)" = "No windows with a pending notification." ]
}

@test "only considers the current session's windows" {
  current work 2
  add_window work 0 1
  add_window work 0 2
  add_window play 1 1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(selected)" ]
  [ "$(messaged)" = "No windows with a pending notification." ]
}
