#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-status"

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: show-option serves the current @mail from $MOCK_DIR/current,
  # set-option records its value into $MOCK_DIR/set (absent if never called),
  # refresh-client counts its calls.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  show-option) cat "$MOCK_DIR/current" 2>/dev/null || true ;;
  set-option) printf '%s' "$4" > "$MOCK_DIR/set" ;;
  refresh-client) echo x >> "$MOCK_DIR/refreshes" ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  export PATH="$MOCK_DIR/bin:$PATH"
}

message() { # message <sender> <status-or-empty>
  printf 'From %s  Tue Nov  3 14:09:01 2026\nSubject: s\n' "$1"
  [ -n "$2" ] && printf 'Status: %s\n' "$2"
  printf '\nbody\n\n'
}

@test "counts unread messages per sender, in order of first arrival" {
  { message agent ''; message daemon ''; message agent ''; } > "$MAIL"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/set")" = "#[range=user|mail]📧 agent (2) · daemon (1)#[norange]" ]
}

@test "does not count read messages" {
  { message agent RO; message daemon ''; } > "$MAIL"
  run "$SCRIPT"
  [ "$(cat "$MOCK_DIR/set")" = "#[range=user|mail]📧 daemon (1)#[norange]" ]
}

@test "clears the option once nothing is unread" {
  message agent R > "$MAIL"
  printf '%s' "#[range=user|mail]📧 agent (1)#[norange]" > "$MOCK_DIR/current"
  run "$SCRIPT"
  [ -f "$MOCK_DIR/set" ]
  [ -z "$(cat "$MOCK_DIR/set")" ]
}

@test "leaves tmux alone when the value has not changed" {
  message agent '' > "$MAIL"
  printf '%s' "#[range=user|mail]📧 agent (1)#[norange]" > "$MOCK_DIR/current"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_DIR/set" ]
  [ ! -f "$MOCK_DIR/refreshes" ]
}

@test "repaints after changing the option" {
  message agent '' > "$MAIL"
  run "$SCRIPT"
  [ -f "$MOCK_DIR/refreshes" ]
}

@test "doubles a # in a sender name so tmux does not read it as a style" {
  message 'a#b' '' > "$MAIL"
  run "$SCRIPT"
  [ "$(cat "$MOCK_DIR/set")" = "#[range=user|mail]📧 a##b (1)#[norange]" ]
}

@test "shows nothing when there is no mailbox" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_DIR/set" ]
}
