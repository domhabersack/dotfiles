#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-feed"
US=$(printf '\037')

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
}

# line_of <n>: the n-th line of the list output, fields joined with "|"
line_of() { "$SCRIPT" | sed -n "${1}p" | tr "$US" '|'; }

@test "prints nothing, successfully, when the mailbox does not exist" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lists a message with index, unread flag, sender, envelope date and subject" {
  cat > "$MAIL" <<'EOF'
From agent@host.local  Tue Nov  3 14:09:01 2026
From: agent <agent@host.local>
Subject: needs API key

body
EOF
  [ "$(line_of 1)" = "1|U|agent|Nov 3 14:09|needs API key" ]
}

@test "numbers messages in file order and reads the R in Status: as read" {
  cat > "$MAIL" <<'EOF'
From agent  Tue Nov  3 14:09:01 2026
Subject: one
Status: R

a

From daemon  Tue Nov  3 15:30:00 2026
Subject: two
Status: O

b
EOF
  [ "$(line_of 1)" = "1|R|agent|Nov 3 14:09|one" ]
  [ "$(line_of 2)" = "2|U|daemon|Nov 3 15:30|two" ]
}

@test "takes the sender from the address inside angle brackets, display name or not" {
  cat > "$MAIL" <<'EOF'
From x  Tue Nov  3 14:09:01 2026
From: "Daemon, The" <daemon@host.local>
Subject: s

b
EOF
  [ "$(line_of 1)" = "1|U|daemon|Nov 3 14:09|s" ]
}

@test "takes the sender from a bare address, with or without a trailing (comment)" {
  cat > "$MAIL" <<'EOF'
From x  Tue Nov  3 14:09:01 2026
From: habersackd@host.local (Dominik Habersack)
Subject: s

b

From y  Tue Nov  3 14:10:00 2026
From: agent@host.local
Subject: s

b
EOF
  [ "$(line_of 1)" = "1|U|habersackd|Nov 3 14:09|s" ]
  [ "$(line_of 2)" = "2|U|agent|Nov 3 14:10|s" ]
}

@test "falls back to the envelope sender without a From: header" {
  cat > "$MAIL" <<'EOF'
From root@host  Tue Nov  3 14:09:01 2026
Subject: s

b
EOF
  [ "$(line_of 1)" = "1|U|root|Nov 3 14:09|s" ]
}

@test "joins a folded subject and fills in an empty one" {
  cat > "$MAIL" <<'EOF'
From a  Tue Nov  3 14:09:01 2026
Subject: needs API key
  for staging

b

From a  Tue Nov  3 14:10:00 2026
Subject:

b
EOF
  [ "$(line_of 1)" = "1|U|a|Nov 3 14:09|needs API key for staging" ]
  [ "$(line_of 2)" = "2|U|a|Nov 3 14:10|(no subject)" ]
}

@test "does not split a message at a body line that starts with From" {
  cat > "$MAIL" <<'EOF'
From a  Tue Nov  3 14:09:01 2026
Subject: one

before
From here on it is still the body
after
EOF
  [ "$("$SCRIPT" | wc -l | tr -d ' ')" = 1 ]
}

@test "--body prints From, Date, Subject and the body of just that message" {
  cat > "$MAIL" <<'EOF'
From a  Tue Nov  3 14:09:01 2026
From: a <a@h>
Date: Tue, 3 Nov 2026 14:09:01 +0100
Subject: one

first body

From b  Tue Nov  3 14:10:00 2026
From: b <b@h>
Subject: two

second body
EOF
  run "$SCRIPT" --body 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"From:    b <b@h>"* ]]
  [[ "$output" == *"Subject: two"* ]]
  [[ "$output" == *"second body"* ]]
  [[ "$output" != *"first body"* ]]
}
