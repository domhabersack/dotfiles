#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-notify-windows"

setup() {
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: serves canned list-sessions / per-session list-windows output
  # this test writes into $MOCK_DIR, records set-option calls into
  # $MOCK_DIR/captured, and no-ops refresh-client. Only shell builtins so it
  # needs no external tools on PATH.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  list-sessions)
    while IFS= read -r ln; do printf '%s\n' "$ln"; done < "$MOCK_DIR/sessions"
    ;;
  list-windows)
    # $3 is the session name (args: list-windows -t <sess> -F <fmt>)
    f="$MOCK_DIR/windows_$3"
    [ -f "$f" ] && while IFS= read -r ln; do printf '%s\n' "$ln"; done < "$f"
    ;;
  set-option)
    # args: set-option -t <sess> status-right <value>
    printf '%s\t%s\n' "$3" "$5" >> "$MOCK_DIR/captured"
    ;;
  refresh-client) : ;;
  *) : ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  : > "$MOCK_DIR/sessions"
  : > "$MOCK_DIR/captured"

  PATH="$MOCK_DIR/bin:$PATH"
}

# add_window <session> <bell-flag> <window-name...>
add_window() {
  sess=$1; flag=$2; shift 2
  printf '%s %s\n' "$flag" "$*" >> "$MOCK_DIR/windows_$sess"
}

set_sessions() {
  printf '%s\n' "$@" > "$MOCK_DIR/sessions"
}

# the last status-right value set for a session
captured_for() {
  grep "^$1	" "$MOCK_DIR/captured" | tail -1 | cut -f2-
}

@test "lists the bell windows' names, dot-joined and bell-prefixed" {
  set_sessions work
  add_window work 0 shell
  add_window work 1 codeshots
  add_window work 1 api
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 codeshots · api#[default]')" ]
}

@test "sets an empty status-right when no window has a pending bell" {
  set_sessions work
  add_window work 0 shell
  add_window work 0 codeshots
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "" ]
}

@test "handles each session independently" {
  set_sessions work play
  add_window work 1 alpha
  add_window play 0 beta
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 alpha#[default]')" ]
  [ "$(captured_for play)" = "" ]
}

@test "preserves a window name that contains spaces" {
  set_sessions work
  add_window work 1 my long window
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 my long window#[default]')" ]
}

@test "sets status-right for every session even when only some have bells" {
  set_sessions work play
  add_window work 0 shell
  add_window play 1 gamma
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "" ]
  [ "$(captured_for play)" = "$(printf '#[fg=colour1]🔔 gamma#[default]')" ]
}
