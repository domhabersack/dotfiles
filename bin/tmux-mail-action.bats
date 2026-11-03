#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-action"
FEED="$BATS_TEST_DIRNAME/tmux-mail-feed"

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock mail: records its arguments, the mailbox it was given in $MAIL and
  # the commands piped to it, so a test
  # can see what would have been done to the mailbox without a real mail (BSD
  # mail isn't on the CI runner).
  cat > "$MOCK_DIR/bin/mail" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$MOCK_DIR/args"
printf '%s\n' "$MAIL" > "$MOCK_DIR/mailbox"
cat > "$MOCK_DIR/stdin"
EOF
  chmod +x "$MOCK_DIR/bin/mail"
  export PATH="$MOCK_DIR/bin:$PATH"

  cat > "$MAIL" <<'EOF'
From agent  Tue Nov  3 14:09:01 2026
Subject: one

a

From daemon  Tue Nov  3 15:30:00 2026
Subject: two
Status: RO

b
EOF
}

line_of() { "$FEED" | sed -n "${1}p"; }

@test "marks an unread message read by typing it" {
  run "$SCRIPT" toggle "$(line_of 1)"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/stdin")" = "$(printf 'set hold\ntype 1\nquit')" ]
}

@test "opens the mailbox as the system mailbox, which takes the delivery lock, not as a file" {
  run "$SCRIPT" toggle "$(line_of 1)"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/args")" = "-N -n" ]
  [ "$(cat "$MOCK_DIR/mailbox")" = "$MAIL" ]
}

@test "marks a read message unread" {
  run "$SCRIPT" toggle "$(line_of 2)"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/stdin")" = "$(printf 'set hold\nunread 2\nquit')" ]
}

@test "deletes a message" {
  run "$SCRIPT" delete "$(line_of 2)"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/stdin")" = "$(printf 'set hold\ndelete 2\nquit')" ]
}

@test "refuses, without touching the mailbox, when a different message is now at that position" {
  stale=$(line_of 1)
  # a delete elsewhere shifted the messages up: position 1 is now "two"
  sed '1,5d' "$MAIL" > "$MAIL.new" && mv "$MAIL.new" "$MAIL"
  run "$SCRIPT" delete "$stale"
  [ "$status" -eq 1 ]
  [ ! -f "$MOCK_DIR/stdin" ]
}

@test "refuses when the read state shown is no longer the real one" {
  stale=$(line_of 1)
  sed 's/^Subject: one$/Subject: one\nStatus: R/' "$MAIL" > "$MAIL.new" && mv "$MAIL.new" "$MAIL"
  run "$SCRIPT" toggle "$stale"
  [ "$status" -eq 1 ]
  [ ! -f "$MOCK_DIR/stdin" ]
}

@test "rejects an unknown action" {
  run "$SCRIPT" archive "$(line_of 1)"
  [ "$status" -eq 2 ]
  [ ! -f "$MOCK_DIR/stdin" ]
}
