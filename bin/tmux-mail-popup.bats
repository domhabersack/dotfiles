#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-popup"
FEED="$BATS_TEST_DIRNAME/tmux-mail-feed"
US=$(printf '\037')
ESC=$(printf '\033')

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
  export TMUX_MAIL_POLL_STAMP="$BATS_TEST_TMPDIR/stamp"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock mail and tmux: mail records that it was called; tmux records its
  # arguments, standing in for the status refresh the --act mode runs
  # afterwards and the message it shows on a refusal.
  cat > "$MOCK_DIR/bin/mail" <<'EOF'
#!/bin/sh
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
  if grep -q '^display-message' "$MOCK_DIR/tmux-calls" 2>/dev/null; then false; fi
}
