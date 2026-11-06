#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case
bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-mail-changed"

setup() {
  export MAIL="$BATS_TEST_TMPDIR/mbox"
  STAMP="$BATS_TEST_TMPDIR/stamp"
  printf 'From agent  Tue Nov  3 14:09:01 2026\nSubject: one\n\na\n' > "$MAIL"
}

@test "reports a change on the first call, then none until the mailbox changes" {
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 0 ]
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 1 ]
}

@test "reports a delivery, which grows the mailbox" {
  "$SCRIPT" "$STAMP"
  printf '\nFrom daemon  Tue Nov  3 15:30:00 2026\nSubject: two\n\nb\n' >> "$MAIL"
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 0 ]
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 1 ]
}

@test "reports a same-size rewrite by its modification time" {
  "$SCRIPT" "$STAMP"
  sed 's/one/eno/' "$MAIL" > "$MAIL.new"
  mv "$MAIL.new" "$MAIL"
  touch -t 203001010000 "$MAIL"
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 0 ]
}

@test "leaves the stamp alone when nothing changed" {
  "$SCRIPT" "$STAMP"
  # A stamp time in the future, so a rewrite (which sets it to now) shows.
  touch -t 203001010000 "$STAMP" "$BATS_TEST_TMPDIR/ref"
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 1 ]
  [ -z "$(find "$BATS_TEST_TMPDIR/ref" -newer "$STAMP")" ]
}

@test "treats a missing mailbox as unchanged after the first call" {
  rm "$MAIL"
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 0 ]
  run "$SCRIPT" "$STAMP"
  [ "$status" -eq 1 ]
}

@test "says nothing on stderr about a missing mailbox" {
  rm "$MAIL"
  run --separate-stderr "$SCRIPT" "$STAMP"
  [ -z "$stderr" ]
}

@test "reports a change when the stamp cannot be written, rather than freezing" {
  mkdir "$BATS_TEST_TMPDIR/locked"
  chmod 500 "$BATS_TEST_TMPDIR/locked"
  run "$SCRIPT" "$BATS_TEST_TMPDIR/locked/stamp"
  [ "$status" -eq 0 ]
  run "$SCRIPT" "$BATS_TEST_TMPDIR/locked/stamp"
  [ "$status" -eq 0 ]
  chmod 700 "$BATS_TEST_TMPDIR/locked"
}
