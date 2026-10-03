#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped state is how @test isolates each case

bats_require_minimum_version 1.5.0

# tmux-locklib had no tests of its own, having been exercised only through its
# callers -- which all take the owner-is-alive path, so the stale-lock handling
# that is the whole point of the library was never covered. These fill that in,
# the no-owner cases especially: seven scripts share this code.

setup() {
  LOCK="$BATS_TEST_TMPDIR/lock"
  # shellcheck source=./tmux-locklib
  . "$BATS_TEST_DIRNAME/tmux-locklib"
}

@test "an unheld lock is not live and can be acquired" {
  run lock_live "$LOCK"
  [ "$status" -eq 1 ]

  lock_acquire "$LOCK"
  [ -d "$LOCK" ]
  [ "$(cat "$LOCK/pid")" = "$$" ]
}

@test "a lock held by a live process is live and cannot be stolen" {
  mkdir -p "$LOCK"
  sleep 30 & owner=$!
  printf '%s\n' "$owner" > "$LOCK/pid"

  run lock_live "$LOCK"
  [ "$status" -eq 0 ]
  run lock_acquire "$LOCK"
  [ "$status" -eq 1 ]
  [ "$(cat "$LOCK/pid")" = "$owner" ]   # still theirs

  kill "$owner" 2>/dev/null; wait "$owner" 2>/dev/null || true
}

@test "a lock whose owner has died is stale and is stolen" {
  mkdir -p "$LOCK"
  sh -c 'exit 0' & dead=$!
  wait "$dead" 2>/dev/null || true
  printf '%s\n' "$dead" > "$LOCK/pid"

  run lock_live "$LOCK"
  [ "$status" -eq 1 ]
  lock_acquire "$LOCK"
  [ "$(cat "$LOCK/pid")" = "$$" ]
}

@test "a lock with no owner recorded yet reads as held, not stale" {
  # mkdir and the write of "pid" are two steps. Reading the gap between them as
  # "stale" let a loser delete a claim that was very much alive.
  mkdir -p "$LOCK"
  ( sleep 0.03; printf '%s\n' "$$" > "$LOCK/pid" ) &
  writer=$!

  run lock_live "$LOCK"
  [ "$status" -eq 0 ]

  wait "$writer" 2>/dev/null || true
}

@test "a lock abandoned with no owner recorded is still stealable" {
  # The flip side: an age test would honour this for a minute, which would make
  # bin/tmux-obsidian-task-toggle (it gives up after a second) fail where it used
  # to steal. Nothing is going to write a pid here, so it must read as stale.
  mkdir -p "$LOCK"

  run lock_live "$LOCK"
  [ "$status" -eq 1 ]
  lock_acquire "$LOCK"
  [ "$(cat "$LOCK/pid")" = "$$" ]
}

@test "acquiring creates a missing parent directory" {
  # A watcher cleaning up after itself removes the per-server directory once it is
  # empty, so a claim beneath it can find its parent gone.
  run lock_acquire "$BATS_TEST_TMPDIR/absent/deeper/lock"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/absent/deeper/lock/pid" ]
}

@test "a second acquire by the same process does not double-acquire" {
  lock_acquire "$LOCK"
  run lock_acquire "$LOCK"
  [ "$status" -eq 1 ]      # we already hold it; it is live
}
