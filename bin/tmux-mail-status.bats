#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-status"

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: display-message serves a fixed server pid (for the stamp's
  # name), show-option serves the current @mail from $MOCK_DIR/current
  # (@mail_short from $MOCK_DIR/current_short),
  # set-option records @mail's value into $MOCK_DIR/set and @mail_short's
  # into $MOCK_DIR/set_short (absent if never called), refresh-client counts
  # its calls.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  display-message) echo 4242 ;;
  show-option)
    if [ "$3" = @mail_short ]; then
      cat "$MOCK_DIR/current_short" 2>/dev/null || true
    else
      cat "$MOCK_DIR/current" 2>/dev/null || true
    fi
    ;;
  set-option)
    if [ "$3" = @mail_short ]; then
      printf '%s' "$4" > "$MOCK_DIR/set_short"
    else
      printf '%s' "$4" > "$MOCK_DIR/set"
    fi
    ;;
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

@test "sets a short form with just the unread total" {
  { message agent ''; message daemon ''; message agent ''; message agent RO; } > "$MAIL"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/set_short")" = "#[range=user|mail]📧 3#[norange]" ]
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
  [ -f "$MOCK_DIR/set_short" ]
  [ -z "$(cat "$MOCK_DIR/set_short")" ]
}

@test "leaves tmux alone when the value has not changed" {
  message agent '' > "$MAIL"
  printf '%s' "#[range=user|mail]📧 agent (1)#[norange]" > "$MOCK_DIR/current"
  printf '%s' "#[range=user|mail]📧 1#[norange]" > "$MOCK_DIR/current_short"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_DIR/set" ]
  [ ! -f "$MOCK_DIR/set_short" ]
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
  [ "$(cat "$MOCK_DIR/set_short")" = "#[range=user|mail]📧 1#[norange]" ]
}

@test "shows nothing when there is no mailbox" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_DIR/set" ]
}

@test "skips parsing a mailbox that has not changed since the last run" {
  message agent '' > "$MAIL"
  "$SCRIPT"
  rm "$MOCK_DIR/set"
  # @mail now differs from what a parse would set, so a set means it parsed.
  printf '%s' 'stale' > "$MOCK_DIR/current"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_DIR/set" ]
}

@test "parses again once the mailbox changes" {
  message agent '' > "$MAIL"
  "$SCRIPT"
  printf '%s' "#[range=user|mail]📧 agent (1)#[norange]" > "$MOCK_DIR/current"
  message daemon '' >> "$MAIL"
  run "$SCRIPT"
  [ "$(cat "$MOCK_DIR/set")" = "#[range=user|mail]📧 agent (1) · daemon (1)#[norange]" ]
}

@test "parses an unchanged mailbox anyway with --force" {
  message agent '' > "$MAIL"
  "$SCRIPT"
  rm "$MOCK_DIR/set"
  printf '%s' 'stale' > "$MOCK_DIR/current"
  run "$SCRIPT" --force
  [ "$(cat "$MOCK_DIR/set")" = "#[range=user|mail]📧 agent (1)#[norange]" ]
}

@test "keeps a separate stamp per tmux server" {
  message agent '' > "$MAIL"
  "$SCRIPT"
  [ -f "$TMPDIR/tmux-mail-status.$(id -u).4242" ]
}

@test "sets a missing short form even when @mail is already current" {
  message agent '' > "$MAIL"
  printf '%s' "#[range=user|mail]📧 agent (1)#[norange]" > "$MOCK_DIR/current"
  run "$SCRIPT" --force
  [ "$(cat "$MOCK_DIR/set_short")" = "#[range=user|mail]📧 1#[norange]" ]
}
