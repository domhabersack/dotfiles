#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-popup"
FEED="$BATS_TEST_DIRNAME/tmux-mail-feed"
US=$(printf '\037')
ESC=$(printf '\033')

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export TMUX_MAIL_POLL_STAMP="$BATS_TEST_TMPDIR/stamp"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock mail and tmux: mail records that it was called (and answers the
  # action's read-only count query, -f, with the mailbox's 2 messages); tmux
  # records its arguments, standing in for the status refresh the --act mode
  # runs afterwards and the message it shows on a refusal.
  cat > "$MOCK_DIR/bin/mail" <<'EOF'
#!/bin/sh
if [ "$3" = -f ]; then
  cat > /dev/null
  echo ' U  2 daemon  Tue Nov  3 15:30  5/80   "newer"'
  exit 0
fi
cat > "$MOCK_DIR/mail-stdin"
EOF
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_DIR/tmux-calls"
EOF
  chmod +x "$MOCK_DIR/bin/mail" "$MOCK_DIR/bin/tmux"
  export PATH="$MOCK_DIR/bin:$PATH"

  cat > "$MAIL" <<'EOF'
From agent  Tue Nov  3 14:09:01 2026
Subject: older

a

From daemon  Tue Nov  3 15:30:00 2026
Subject: newer
Status: RO

b
EOF
}

plain() { sed "s/$ESC\[[0-9;]*m//g"; }

@test "--list puts the newest message first" {
  run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | sed -n 1p | plain)" == *newer* ]]
  [[ "$(printf '%s\n' "$output" | sed -n 2p | plain)" == *older* ]]
}

@test "--list marks unread messages with a dot and leaves read ones unmarked" {
  run "$SCRIPT" --list
  [[ "$(printf '%s\n' "$output" | sed -n 1p | cut -d "$US" -f1 | plain)" != *●* ]]
  [[ "$(printf '%s\n' "$output" | sed -n 2p | cut -d "$US" -f1 | plain)" == *●* ]]
}

@test "--list follows each display text with the message’s own feed line" {
  run "$SCRIPT" --list
  [ "$(printf '%s\n' "$output" | sed -n 2p | cut -d "$US" -f2-)" = "$("$FEED" | sed -n 1p)" ]
}

@test "--poll reloads the first time, then ignores until the mailbox changes" {
  run "$SCRIPT" --poll
  [[ "$output" == reload-sync* ]]
  run "$SCRIPT" --poll
  [ "$output" = ignore ]
  printf '\nFrom x  Tue Nov  3 16:00:00 2026\nSubject: s\n\nb\n' >> "$MAIL"
  run "$SCRIPT" --poll
  [[ "$output" == reload-sync* ]]
}

@test "--poll reloads for a same-size change, by its modification time" {
  run "$SCRIPT" --poll
  sed 's/older/olden/' "$MAIL" > "$MAIL.new"
  mv "$MAIL.new" "$MAIL"
  touch -t 203001010000 "$MAIL"
  run "$SCRIPT" --poll
  [[ "$output" == reload-sync* ]]
}

@test "--act re-renders the footer with --force, so its own change always shows" {
  line="x${US}$("$FEED" | sed -n 1p)"
  # A run first, so the footer's own check has seen this mailbox: the fake mail
  # changes nothing, so only --force makes the run inside --act parse again.
  "$BATS_TEST_DIRNAME/tmux-mail-status"
  : > "$MOCK_DIR/tmux-calls"
  run "$SCRIPT" --act toggle "$line"
  [ "$status" -eq 0 ]
  grep -q '^set-option -g @mail ' "$MOCK_DIR/tmux-calls"
}

@test "--poll leaves the list alone while someone is typing" {
  FZF_IDLE_TIME_MS=100 run "$SCRIPT" --poll
  [ "$output" = ignore ]
}

@test "--act reloads after changing a message, and that change is not a second reload" {
  line="x${US}$("$FEED" | sed -n 1p)"
  run "$SCRIPT" --act toggle "$line"
  [ "$status" -eq 0 ]
  [[ "$output" == reload-sync* ]]
  [ -f "$MOCK_DIR/mail-stdin" ]
  run "$SCRIPT" --poll
  [ "$output" = ignore ]
}

@test "--act says so and changes nothing for a message that is no longer there" {
  line="x${US}9${US}U${US}nobody${US}Jan 1 00:00${US}gone"
  run "$SCRIPT" --act delete "$line"
  [ "$status" -eq 0 ]
  [[ "$output" == reload-sync* ]]
  [ ! -f "$MOCK_DIR/mail-stdin" ]
  grep -q '^display-message .*nothing done' "$MOCK_DIR/tmux-calls"
}

@test "--act shows no message when the change goes through" {
  line="x${US}$("$FEED" | sed -n 1p)"
  run "$SCRIPT" --act toggle "$line"
  [ "$status" -eq 0 ]
  if grep -q 'nothing done' "$MOCK_DIR/tmux-calls" 2>/dev/null; then false; fi
}

@test "without fzf, opens mail with hold set and sources a user rc whose path has a space" {
  home="$BATS_TEST_TMPDIR/my home"
  mkdir -p "$home"
  printf 'set ask\n' > "$home/.mailrc"
  cat > "$MOCK_DIR/bin/mail" <<'MOCK'
#!/bin/sh
cat "$MAILRC" > "$MOCK_DIR/mailrc"
MOCK
  HOME="$home" PATH="$MOCK_DIR/bin:/usr/bin:/bin" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_DIR/mailrc")" = "$(printf 'source "%s"\nset hold' "$home/.mailrc")" ]
}

@test "without fzf, sources an rc named by MAILRC instead of ~/.mailrc" {
  printf 'set ask\n' > "$BATS_TEST_TMPDIR/rc"
  cat > "$MOCK_DIR/bin/mail" <<'MOCK'
#!/bin/sh
cat "$MAILRC" > "$MOCK_DIR/mailrc"
MOCK
  MAILRC="$BATS_TEST_TMPDIR/rc" HOME="$BATS_TEST_TMPDIR" PATH="$MOCK_DIR/bin:/usr/bin:/bin" run "$SCRIPT"
  [ "$(cat "$MOCK_DIR/mailrc")" = "$(printf 'source "%s"\nset hold' "$BATS_TEST_TMPDIR/rc")" ]
}
