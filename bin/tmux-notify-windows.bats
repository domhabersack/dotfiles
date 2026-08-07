#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-notify-windows"

setup() {
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: serves canned list-sessions / list-windows output from windows
  # this test adds, tracks each window's @bell_at in its own bellat_<id> file
  # (so set-window-option can read-modify-write it), records set-option calls
  # into $MOCK_DIR/captured, and no-ops refresh-client. Only shell builtins so
  # it needs no external tools on PATH.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
bell_at_of() { cat "$MOCK_DIR/bellat_$1" 2>/dev/null || true; }

case "$1" in
  list-sessions)
    while IFS= read -r ln; do printf '%s\n' "$ln"; done < "$MOCK_DIR/sessions"
    ;;
  list-windows)
    if [ "$2" = "-a" ]; then
      # args: list-windows -a -F <fmt>, only the stamping pass's own format
      while IFS='	' read -r sess wid flag name; do
        printf '%s %s %s\n' "$flag" "$wid" "$(bell_at_of "$wid")"
      done < "$MOCK_DIR/windows"
    else
      # args: list-windows -t <sess> -F <fmt>
      sess="$3"
      while IFS='	' read -r s wid flag name; do
        [ "$s" = "$sess" ] || continue
        printf '%s\t%s\t%s\n' "$flag" "$(bell_at_of "$wid")" "$name"
      done < "$MOCK_DIR/windows"
    fi
    ;;
  set-window-option)
    # args: set-window-option -t <wid> @bell_at <value>  OR  -t <wid> -u @bell_at
    wid="$3"
    if [ "$4" = "-u" ]; then
      rm -f "$MOCK_DIR/bellat_$wid"
    else
      printf '%s' "$5" > "$MOCK_DIR/bellat_$wid"
    fi
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
  : > "$MOCK_DIR/windows"
  : > "$MOCK_DIR/captured"

  PATH="$MOCK_DIR/bin:$PATH"
}

# add_window <session> <window-id> <bell-flag> <bell-at-or-empty> <name...>
add_window() {
  sess=$1; wid=$2; flag=$3; bell_at=$4; shift 4
  printf '%s\t%s\t%s\t%s\n' "$sess" "$wid" "$flag" "$*" >> "$MOCK_DIR/windows"
  if [ -n "$bell_at" ]; then printf '%s' "$bell_at" > "$MOCK_DIR/bellat_$wid"; fi
}

set_sessions() {
  printf '%s\n' "$@" > "$MOCK_DIR/sessions"
}

# the last status-right value set for a session
captured_for() {
  grep "^$1	" "$MOCK_DIR/captured" | tail -1 | cut -f2-
}

@test "lists the bell windows oldest ring first, not insertion order" {
  set_sessions work
  add_window work @1 1 200 codeshots
  add_window work @2 1 100 api
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 api · codeshots#[default]')" ]
}

@test "sets an empty status-right when no window has a pending bell" {
  set_sessions work
  add_window work @1 0 "" shell
  add_window work @2 0 "" codeshots
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "" ]
}

@test "handles each session independently" {
  set_sessions work play
  add_window work @1 1 100 alpha
  add_window play @2 0 "" beta
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 alpha#[default]')" ]
  [ "$(captured_for play)" = "" ]
}

@test "preserves a window name that contains spaces" {
  set_sessions work
  add_window work @1 1 100 my long window
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 my long window#[default]')" ]
}

@test "sets status-right for every session even when only some have bells" {
  set_sessions work play
  add_window work @1 0 "" shell
  add_window play @2 1 100 gamma
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for work)" = "" ]
  [ "$(captured_for play)" = "$(printf '#[fg=colour1]🔔 gamma#[default]')" ]
}

@test "stamps a freshly-ringing window's queue position" {
  set_sessions work
  add_window work @1 1 "" fresh
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -s "$MOCK_DIR/bellat_@1" ]
  [ "$(captured_for work)" = "$(printf '#[fg=colour1]🔔 fresh#[default]')" ]
}

@test "does not restamp a window that is still ringing" {
  set_sessions work
  add_window work @1 1 100 fresh
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/bellat_@1")" = "100" ]
}

@test "clears the queue stamp once the bell clears" {
  set_sessions work
  add_window work @1 0 100 done
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_DIR/bellat_@1" ]
}
