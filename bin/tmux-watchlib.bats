#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped state is how @test isolates each case

bats_require_minimum_version 1.5.0

setup() {
  # The watcher child sources the library by absolute $HOME path, so fake $HOME
  # and copy it in -- otherwise it resolves to the author's real checkout.
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.dotfiles/bin" "$MOCK_DIR/bin"
  cp "$BATS_TEST_DIRNAME/tmux-watchlib" "$HOME/.dotfiles/bin/tmux-watchlib"

  # State goes under the test's own tmpdir, never /tmp, so a run can never
  # disturb the watchers of a real tmux session on this machine.
  export TMUX_WATCH_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$TMUX_WATCH_DIR"

  # Mock tmux: `has-session` succeeds while $MOCK_DIR/server-alive exists. That
  # is the only subcommand the library calls.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  has-session) [ -f "$MOCK_DIR/server-alive" ] ;;
  *) : ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  PATH="$MOCK_DIR/bin:$PATH"
  : > "$MOCK_DIR/server-alive"

  export TMUX="/tmp/fake-socket,4242,0"

  # shellcheck source=./tmux-watchlib
  . "$HOME/.dotfiles/bin/tmux-watchlib"
}

teardown() {
  # Stop anything a test spawned, so no test leaves a loop running.
  for f in "$TMUX_WATCH_DIR"/*/*; do
    [ -f "$f" ] || continue
    p=$(cat "$f" 2>/dev/null)
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  return 0
}

# Wait up to ~2s for a condition, so tests never depend on a fixed sleep.
wait_for() {
  for _ in $(seq 40); do
    if "$@"; then return 0; fi
    sleep 0.05
  done
  return 1
}

pidfile_of() { printf '%s/%s' "$(_watch_dir)" "$1"; }
pid_gone() { ! kill -0 "$1" 2>/dev/null; }
recorded_pid() { cat "$(pidfile_of "$1")" 2>/dev/null; }

@test "watch_spawn starts a watcher carrying its own marker" {
  watch_spawn demo 'while watch_alive; do sleep 0.2; done'

  [ -f "$(pidfile_of demo)" ]
  pid=$(recorded_pid demo)
  [ -n "$pid" ]
  kill -0 "$pid"

  # the marker is what the guard recognises the process by, and it has to still
  # be there after nohup execs the shell it wraps
  sleep 0.3
  cmd=$(ps -o command= -p "$pid")
  [[ "$cmd" == *": tmux-watch=demo;"* ]]
}

@test "the guard recognises its own watcher after nohup execs" {
  # nohup renders as "nohup sh -c ..." before the exec and "sh -c ..." after;
  # a guard keyed on the whole command line would miss its own watcher here and
  # spawn a duplicate on every config reload
  watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  first=$(recorded_pid demo)

  sleep 0.3   # let nohup exec
  [[ "$(ps -o command= -p "$first")" != nohup* ]]

  watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  [ "$(recorded_pid demo)" = "$first" ]
}

@test "a second watch_spawn is a no-op while the first is running" {
  watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  first=$(recorded_pid demo)

  watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  second=$(recorded_pid demo)

  [ "$first" = "$second" ]
}

@test "a dead pid in the pidfile does not block a new watcher" {
  mkdir -p "$(_watch_dir)"
  # a pid that has certainly exited
  sh -c 'exit 0' & dead=$!
  wait "$dead" 2>/dev/null || true
  printf '%s\n' "$dead" > "$(pidfile_of demo)"

  watch_spawn demo 'while watch_alive; do sleep 0.2; done'

  [ "$(recorded_pid demo)" != "$dead" ]
  kill -0 "$(recorded_pid demo)"
}

@test "a live but unrelated pid (recycled) does not block a new watcher" {
  mkdir -p "$(_watch_dir)"
  sleep 30 & foreign=$!
  printf '%s\n' "$foreign" > "$(pidfile_of demo)"

  watch_spawn demo 'while watch_alive; do sleep 0.2; done'

  mine=$(recorded_pid demo)
  [ "$mine" != "$foreign" ]
  kill -0 "$mine"
  kill "$foreign" 2>/dev/null || true
}

@test "the watcher exits on its own once its tmux server is gone" {
  watch_spawn demo 'while watch_alive; do sleep 0.1; done'
  pid=$(recorded_pid demo)
  kill -0 "$pid"

  rm -f "$MOCK_DIR/server-alive"      # the server goes away

  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
}

@test "the watcher keeps running while its server is alive" {
  watch_spawn demo 'while watch_alive; do sleep 0.1; done'
  pid=$(recorded_pid demo)

  sleep 0.5
  kill -0 "$pid"
}

@test "two tmux servers get independent watchers" {
  TMUX="/tmp/socket-a,111,0" watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  TMUX="/tmp/socket-b,222,0" watch_spawn demo 'while watch_alive; do sleep 0.2; done'

  a=$(TMUX="/tmp/socket-a,111,0" recorded_pid demo)
  b=$(TMUX="/tmp/socket-b,222,0" recorded_pid demo)

  [ -n "$a" ] && [ -n "$b" ]
  [ "$a" != "$b" ]
  kill -0 "$a"
  kill -0 "$b"
  kill "$a" "$b" 2>/dev/null || true
}

@test "a restarted server on the same socket gets its own watcher" {
  # same socket path, different server pid -- the old server's state must not
  # be mistaken for the new server's
  TMUX="/tmp/same-socket,111,0" watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  TMUX="/tmp/same-socket,222,0" watch_spawn demo 'while watch_alive; do sleep 0.2; done'

  old=$(TMUX="/tmp/same-socket,111,0" recorded_pid demo)
  new=$(TMUX="/tmp/same-socket,222,0" recorded_pid demo)

  [ "$old" != "$new" ]
  kill "$old" "$new" 2>/dev/null || true
}

@test "watch_alive tracks the mocked server state" {
  run watch_alive
  [ "$status" -eq 0 ]

  rm -f "$MOCK_DIR/server-alive"
  run watch_alive
  [ "$status" -eq 1 ]
}

@test "outside tmux the state lands in the nosrv bucket and watch_alive is true" {
  unset TMUX
  [[ "$(_watch_dir)" == *tmux-watch-nosrv ]]

  # no server to outlive, so a hand-started watcher is not killed off
  run watch_alive
  [ "$status" -eq 0 ]

  watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  kill -0 "$(recorded_pid demo)"
}

@test "state never lands in /tmp when TMUX_WATCH_DIR is set" {
  watch_spawn demo 'while watch_alive; do sleep 0.2; done'
  [[ "$(_watch_dir)" == "$TMUX_WATCH_DIR"/* ]]
}
