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
  # tmux-watchlib sources tmux-locklib for the spawn claim, so it has to be
  # reachable under the fake $HOME as well
  cp "$BATS_TEST_DIRNAME/tmux-locklib" "$HOME/.dotfiles/bin/tmux-locklib"

  # State goes under the test's own tmpdir, so a run can never disturb the
  # watchers of a real tmux session on this machine.
  export TMUX_WATCH_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$TMUX_WATCH_DIR"

  # Mock tmux. The library only ever calls `display-message -p '#{pid}'`, to ask
  # which server is answering on our socket.
  # Answers per socket, the way a real tmux does: each fake server has its own
  # pid file, so one server's watcher cannot be told another's pid.
  cat > "$MOCK_DIR/bin/tmux" <<'MOCKTMUX'
#!/bin/sh
case "$1" in
  display-message)
    sock=${TMUX%%,*}
    pidfile="$MOCK_DIR/pid-$(basename "$sock")"
    if [ -f "$MOCK_DIR/server-flaky" ]; then
      exit 1                      # fails without saying why: inconclusive
    fi
    if [ ! -f "$pidfile" ]; then
      # what the real tmux says -- which, deliberately, watch_alive does NOT
      # treat as definite, because tmux says it for timeouts too
      echo "no server running on $sock" >&2
      exit 1
    fi
    cat "$pidfile"
    ;;
  *) : ;;
esac
MOCKTMUX
  chmod +x "$MOCK_DIR/bin/tmux"

  # Mock fswatch: never exits on its own, like the real one.
  cat > "$MOCK_DIR/bin/fswatch" <<'MOCKFSW'
#!/bin/sh
while :; do sleep 0.2; done
MOCKFSW
  chmod +x "$MOCK_DIR/bin/fswatch"

  PATH="$MOCK_DIR/bin:$PATH"

  # Our server is pid 4242 on $MOCK_DIR/socket, and it is up. The socket path has
  # to exist: watch_alive treats its disappearance as the one unambiguous sign
  # that the server is gone.
  export SOCK="$MOCK_DIR/socket"
  export OTHER_SOCK="$MOCK_DIR/other-socket"
  : > "$SOCK"
  : > "$OTHER_SOCK"
  # A short grace period, so the "gave up waiting" paths are testable; the real
  # default is two minutes.
  export TMUX_WATCH_GRACE=2

  export TMUX="$SOCK,4242,0"
  export OTHER_TMUX="$OTHER_SOCK,777,0"
  echo 4242 > "$MOCK_DIR/pid-socket"
  echo 777  > "$MOCK_DIR/pid-other-socket"

  # shellcheck source=./tmux-watchlib
  . "$HOME/.dotfiles/bin/tmux-watchlib"
}

teardown() {
  # Stop every watcher this test started by taking its server away, and wait for
  # each to remove its own state file on the way out.
  #
  # Deliberately no kill and no pkill anywhere in here. Signalling a recorded pid
  # is unsafe in exactly the way this library exists to fix: between a test
  # running and teardown, that pid can be recycled onto any process on the
  # machine. Under the load of a full suite run that is not hypothetical -- it
  # repeatedly killed the watchers of the real tmux session on this machine. The
  # watchers already know how to stop themselves, so let them.
  rm -f "$SOCK" "$OTHER_SOCK" "$MOCK_DIR"/pid-* "$MOCK_DIR/server-flaky"

  for _ in $(seq 100); do
    [ -z "$(ls "$TMUX_WATCH_DIR"/*/* 2>/dev/null)" ] && break
    sleep 0.05
  done
  return 0
}

# Wait up to ~4s for a condition, so tests never depend on a fixed sleep.
wait_for() {
  for _ in $(seq 80); do
    if "$@"; then return 0; fi
    sleep 0.05
  done
  return 1
}

pidfile_of()   { printf '%s/%s' "$(_watch_dir)" "$1"; }
recorded_pid() { cat "$(pidfile_of "$1")" 2>/dev/null; }
pid_gone()     { ! kill -0 "$1" 2>/dev/null; }
has_marker()   { ps -o command= -p "$1" 2>/dev/null | grep -q "tmux-watch=$2@"; }
spawned()      { [ -n "$(recorded_pid "$1")" ]; }
# Children of a dead process are reparented to pid 1, so `pgrep -P <dead pid>` is
# empty whether they were reaped or orphaned. Capture the pids while the parent
# lives, then assert on those pids directly.
all_gone()     { for _p in $1; do kill -0 "$_p" 2>/dev/null && return 1; done; return 0; }
gone_file()    { [ ! -f "$1" ]; }
# state dir for our socket but another server pid, without hardcoding the key
sib_dir()      { printf '%s/%s-%s' "$TMUX_WATCH_DIR" "$(printf '%s' "$SOCK" | tr '/' '_')" "$1"; }
other_dir()    { TMUX="$OTHER_TMUX" _watch_dir; }

TICK='while watch_alive; do sleep 0.1; done'

@test "watch_spawn starts a watcher carrying its own marker" {
  watch_spawn demo "$TICK"

  pid=$(recorded_pid demo)
  [ -n "$pid" ]
  kill -0 "$pid"

  # the marker is how the guard recognises the process, and it has to survive
  # nohup exec'ing the shell it wraps
  run wait_for has_marker "$pid" demo
  [ "$status" -eq 0 ]
}

@test "the guard recognises its own watcher after nohup execs" {
  # nohup renders as "nohup sh -c ..." before the exec and "sh -c ..." after; a
  # guard keyed on the whole command line would miss its own watcher here and
  # spawn a duplicate on every config reload
  watch_spawn demo "$TICK"
  first=$(recorded_pid demo)

  run wait_for has_marker "$first" demo
  [ "$status" -eq 0 ]
  [[ "$(ps -o command= -p "$first")" != nohup* ]]

  watch_spawn demo "$TICK"
  [ "$(recorded_pid demo)" = "$first" ]
}

@test "a second watch_spawn is a no-op while the first is running" {
  watch_spawn demo "$TICK"
  first=$(recorded_pid demo)
  run wait_for has_marker "$first" demo

  watch_spawn demo "$TICK"
  [ "$(recorded_pid demo)" = "$first" ]
}

@test "a dead pid in the state file does not block a new watcher" {
  mkdir -p "$(_watch_dir)"
  sh -c 'exit 0' & dead=$!
  wait "$dead" 2>/dev/null || true
  printf '%s\n' "$dead" > "$(pidfile_of demo)"

  watch_spawn demo "$TICK"

  [ "$(recorded_pid demo)" != "$dead" ]
  kill -0 "$(recorded_pid demo)"
}

@test "a live but unrelated pid (recycled) does not block a new watcher" {
  mkdir -p "$(_watch_dir)"
  sleep 30 & foreign=$!
  printf '%s\n' "$foreign" > "$(pidfile_of demo)"

  watch_spawn demo "$TICK"

  mine=$(recorded_pid demo)
  [ "$mine" != "$foreign" ]
  kill -0 "$mine"
  kill "$foreign" 2>/dev/null; wait "$foreign" 2>/dev/null || true
}

@test "another server's watcher does not satisfy our guard" {
  # the marker names the server as well as the watcher, so one server's watcher
  # can never stand in for another's after a pid is recycled
  TMUX="$OTHER_TMUX" watch_spawn demo "$TICK"
  theirs=$(cat "$(other_dir)/demo")
  run wait_for has_marker "$theirs" demo
  [ "$status" -eq 0 ]

  mkdir -p "$(_watch_dir)"
  printf '%s\n' "$theirs" > "$(pidfile_of demo)"   # plant it as if it were ours

  watch_spawn demo "$TICK"

  [ "$(recorded_pid demo)" != "$theirs" ]
}

@test "the watcher exits on its own once its server is gone" {
  watch_spawn demo "$TICK"
  pid=$(recorded_pid demo)
  kill -0 "$pid"

  rm -f "$MOCK_DIR/pid-socket" "$SOCK"   # server gone, socket removed with it

  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
}

@test "the watcher exits when a DIFFERENT server takes over its socket" {
  # the defect this guards: probing reachability rather than identity let a
  # watcher adopt its successor and tick forever beside the new server's own
  watch_spawn demo "$TICK"
  pid=$(recorded_pid demo)

  echo 9999 > "$MOCK_DIR/pid-socket"   # restarted server, same socket, new pid

  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
}

@test "the watcher keeps running while its own server is alive" {
  watch_spawn demo "$TICK"
  pid=$(recorded_pid demo)

  sleep 0.6
  kill -0 "$pid"
}

@test "a watcher removes its own state file as it exits" {
  watch_spawn demo "$TICK"
  pid=$(recorded_pid demo)
  [ -f "$(pidfile_of demo)" ]

  rm -f "$MOCK_DIR/pid-socket" "$SOCK"

  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
  run wait_for gone_file "$(pidfile_of demo)"
  [ "$status" -eq 0 ]
}

@test "state belonging to a server that is gone is reaped" {
  # leftovers on our socket, under a pid nothing is using
  dead=31999
  while kill -0 "$dead" 2>/dev/null; do dead=$((dead - 1)); done
  dead_dir=$(sib_dir "$dead")
  mkdir -p "$dead_dir"; printf '1\n' > "$dead_dir/demo"

  watch_spawn demo "$TICK"

  [ ! -d "$dead_dir" ]
}

@test "state belonging to a live sibling server is left alone" {
  live_dir=$(sib_dir "$$")                            # our own pid: certainly alive
  mkdir -p "$live_dir"; printf '1\n' > "$live_dir/demo"

  watch_spawn demo "$TICK"

  [ -d "$live_dir" ]
}

@test "concurrent starts produce exactly one watcher" {
  # Counted by what each watcher writes when it starts, not by pgrep: ps renders
  # a subshell with its parent's command line, so a marker match counts subshells
  # (a command substitution, a backgrounded pipeline) as extra watchers.
  for _ in 1 2 3 4 5; do
    # shellcheck disable=SC2016 # single-quoted on purpose: $MOCK_DIR expands in the watcher child
    ( watch_spawn demo 'echo started >> "$MOCK_DIR/starts"; '"$TICK" ) &
  done
  wait

  run wait_for spawned demo
  [ "$status" -eq 0 ]
  sleep 0.5
  [ "$(wc -l < "$MOCK_DIR/starts" | tr -d ' ')" -eq 1 ]
}

@test "a watcher is started, not suppressed, when ps cannot identify the pid" {
  # ps telling us nothing must fail towards a spare watcher (noisy, but self-
  # correcting) rather than towards none at all (a silently dead feature)
  mkdir -p "$(_watch_dir)"
  sleep 30 & foreign=$!
  printf '%s\n' "$foreign" > "$(pidfile_of demo)"
  cat > "$MOCK_DIR/bin/ps" <<'MOCKPS'
#!/bin/sh
exit 0
MOCKPS
  chmod +x "$MOCK_DIR/bin/ps"

  watch_spawn demo "$TICK"

  [ "$(recorded_pid demo)" != "$foreign" ]
  kill "$foreign" 2>/dev/null; wait "$foreign" 2>/dev/null || true
}

@test "watch_spawn reports failure when the state dir cannot be created" {
  : > "$BATS_TEST_TMPDIR/blocked"          # a file where a directory must go
  export TMUX_WATCH_DIR="$BATS_TEST_TMPDIR/blocked/state"

  run watch_spawn demo "$TICK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot create"* ]]
}

@test "watch_alive tracks which server is answering" {
  run watch_alive
  [ "$status" -eq 0 ]

  echo 9999 > "$MOCK_DIR/pid-socket"       # someone else's server
  run watch_alive
  [ "$status" -eq 1 ]

  # back to our own server, so the next assertion can only pass via the socket
  # check and not via a pid mismatch
  echo 4242 > "$MOCK_DIR/pid-socket"
  run watch_alive
  [ "$status" -eq 0 ]
  rm -f "$SOCK"                            # socket gone: the unambiguous case
  run watch_alive
  [ "$status" -eq 1 ]
}

@test "an inconclusive probe does not kill the watcher" {
  # the regression this guards: treating any failed probe as "server gone" made
  # watchers die off whenever the machine was too busy for tmux to answer
  # A grace well clear of the wait below: sleeping for exactly one grace period
  # asserts liveness at the instant it expires, which fails whenever the watcher
  # gets scheduled first (observed roughly one run in twelve).
  TMUX_WATCH_GRACE=10 \
    watch_spawn demo 'while watch_alive; do sleep 1; done'
  pid=$(recorded_pid demo)
  run wait_for has_marker "$pid" demo
  [ "$status" -eq 0 ]

  : > "$MOCK_DIR/server-flaky"      # tmux fails without saying there is no server
  sleep 2
  kill -0 "$pid"                    # still running

  rm -f "$MOCK_DIR/server-flaky"    # and it recovers rather than having given up
  sleep 0.5
  kill -0 "$pid"
}

@test "a long run of inconclusive probes eventually ends the watcher" {
  # tmux does not unlink its socket when it exits, so a server that quit and was
  # not replaced leaves one that answers nothing: only the grace period running
  # out tells a watcher to stop. Called directly, not via `run`, because the
  # "since when" timestamp lives in the calling shell and `run` would evaluate
  # each call in a subshell that discards it.
  : > "$MOCK_DIR/server-flaky"

  watch_alive                       # first inconclusive probe starts the clock
  sleep 1
  watch_alive                       # still inside the 2s grace
  sleep 2
  if watch_alive; then return 1; fi  # grace exhausted
}

@test "one good probe resets the grace period" {
  : > "$MOCK_DIR/server-flaky"
  watch_alive                              # clock starts, 1 failed probe
  sleep 2                                  # ... and would be exhausted next call

  rm -f "$MOCK_DIR/server-flaky"           # tmux answers again
  watch_alive                              # definite answer: resets clock AND count

  : > "$MOCK_DIR/server-flaky"
  watch_alive                              # so we are inside a fresh grace again
  watch_alive
  sleep 2
  if watch_alive; then return 1; fi        # and the fresh grace still expires
}

@test "elapsed time alone does not end a watcher" {
  # the regression this guards: a suspended laptop comes back with hours of wall
  # time added, and a watcher that had seen one inconclusive probe before the lid
  # closed would have given up on the first one after it -- on a healthy server
  : > "$MOCK_DIR/server-flaky"
  watch_alive                              # one failed probe, clock starts
  sleep 2                                  # longer than the whole grace

  # the clock is exhausted, but one more failed probe is not enough to conclude
  watch_alive
}

@test "an fswatch-shaped watcher exits and leaves no fswatch behind" {
  # the defect this guards: reading fswatch's output directly meant the loop
  # noticed a dead server only on the next file event, and left fswatch running
  # shellcheck disable=SC2016 # single-quoted on purpose: evaluated in the child
  watch_spawn fsdemo \
    'fswatch -o /dev/null | while read -r _; do :; done &
     pipeline=$!
     while watch_alive && kill -0 "$pipeline" 2>/dev/null; do sleep 0.1; done'
  pid=$(recorded_pid fsdemo)
  run wait_for has_marker "$pid" fsdemo
  [ "$status" -eq 0 ]
  kids=$(pgrep -P "$pid")
  [ -n "$kids" ]                                 # fswatch is running under it

  rm -f "$MOCK_DIR/pid-socket" "$SOCK"

  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
  run wait_for all_gone "$kids"
  [ "$status" -eq 0 ]
}

@test "a watcher is killable by SIGTERM and cleans up as it goes" {
  # the regression this guards: a trap that cleaned up and returned swallowed the
  # signal, leaving a watcher that nothing short of SIGKILL could stop.
  #
  # Note this cannot fail on macOS for the *cleanup* half: bash runs an EXIT trap
  # even for an untrapped SIGTERM, so removing the TERM trap still cleans up here.
  # On dash -- /bin/sh on the CI runner -- it does not, which is where this half
  # of the assertion earns its keep.
  watch_spawn demo "$TICK"
  pid=$(recorded_pid demo)
  run wait_for has_marker "$pid" demo
  [ "$status" -eq 0 ]

  kill "$pid"
  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
  run wait_for gone_file "$(pidfile_of demo)"
  [ "$status" -eq 0 ]
}

@test "a watcher killed by SIGTERM still reaps its children" {
  # the regression this guards: reaping only at the end of the body skipped the
  # signal path, so a watcher told to stop left its fswatch running forever --
  # holding a valid marker whose state file was gone, invisible to the guard
  # shellcheck disable=SC2016 # single-quoted on purpose: evaluated in the child
  watch_spawn fsdemo \
    'fswatch -o /dev/null | while read -r _; do :; done &
     pipeline=$!
     while watch_alive && kill -0 "$pipeline" 2>/dev/null; do sleep 0.1; done'
  pid=$(recorded_pid fsdemo)
  run wait_for has_marker "$pid" fsdemo
  [ "$status" -eq 0 ]
  kids=$(pgrep -P "$pid")
  [ -n "$kids" ]

  kill "$pid"
  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
  run wait_for all_gone "$kids"
  [ "$status" -eq 0 ]
}

@test "a watcher stops when the thing it supervises dies" {
  # the regression this guards: backgrounding fswatch left nothing supervising
  # it, so a watcher whose fswatch had died looked healthy to the guard and no
  # reload could replace it -- the feature stayed dead silently
  # shellcheck disable=SC2016 # single-quoted on purpose: evaluated in the child
  watch_spawn fsdemo \
    'fswatch -o /dev/null | while read -r _; do :; done &
     pipeline=$!
     while watch_alive && kill -0 "$pipeline" 2>/dev/null; do sleep 0.1; done'
  pid=$(recorded_pid fsdemo)
  run wait_for has_marker "$pid" fsdemo
  [ "$status" -eq 0 ]

  # kill the fswatch out from under it
  for c in $(pgrep -P "$pid"); do
    ps -o command= -p "$c" | grep -q fswatch && kill -9 "$c"
  done

  run wait_for pid_gone "$pid"
  [ "$status" -eq 0 ]
  run wait_for gone_file "$(pidfile_of fsdemo)"
  [ "$status" -eq 0 ]
}

@test "the spawn claim is released once the watcher is up" {
  watch_spawn demo "$TICK"
  run wait_for gone_file "$(pidfile_of demo).claim/pid"
  [ "$status" -eq 0 ]
  [ ! -d "$(pidfile_of demo).claim" ]
}

@test "a watcher that never becomes recognisable does not wedge the claim" {
  # the hold loop is bounded, so a child that exits immediately costs a moment
  # and leaves the name free rather than claimed forever
  watch_spawn gone 'exit 0'
  [ ! -d "$(pidfile_of gone).claim" ]
}

@test "state left by a dead server on another socket is reaped too" {
  # a throwaway server on its own socket would otherwise leave an entry that
  # nothing ever looks at again
  dead=31999
  while kill -0 "$dead" 2>/dev/null; do dead=$((dead - 1)); done
  other="$TMUX_WATCH_DIR/_some_other_socket-$dead"
  mkdir -p "$other"; printf '1\n' > "$other/demo"

  watch_spawn demo "$TICK"

  [ ! -d "$other" ]
}

@test "outside tmux the state lands in the nosrv bucket and watch_alive is true" {
  unset TMUX
  [[ "$(_watch_dir)" == */nosrv ]]

  run watch_alive
  [ "$status" -eq 0 ]

  # This watcher has no server to lose, so teardown cannot stop it. Give it a
  # body that ends on its own instead of one that waits on watch_alive.
  # shellcheck disable=SC2016 # single-quoted on purpose: evaluated in the child
  watch_spawn demo 'i=0; while [ "$i" -lt 5 ]; do i=$((i + 1)); sleep 0.05; done'
  pid=$(recorded_pid demo)
  [ -n "$pid" ]
  run wait_for gone_file "$(pidfile_of demo)"
  [ "$status" -eq 0 ]
}

@test "state honours TMUX_WATCH_DIR" {
  watch_spawn demo "$TICK"
  [[ "$(_watch_dir)" == "$TMUX_WATCH_DIR"/* ]]
}

@test "the default state location is durable, not /tmp" {
  # /tmp is purged by macOS's periodic cleaner, which deleted state from under a
  # running watcher and let the guard start a second one
  ( unset TMUX_WATCH_DIR
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg"
    export XDG_STATE_HOME
    # shellcheck source=./tmux-watchlib
    . "$HOME/.dotfiles/bin/tmux-watchlib"
    [ "$TMUX_WATCH_DIR" = "$XDG_STATE_HOME/tmux-watch" ] )

  ( unset TMUX_WATCH_DIR XDG_STATE_HOME
    # shellcheck source=./tmux-watchlib
    . "$HOME/.dotfiles/bin/tmux-watchlib"
    [ "$TMUX_WATCH_DIR" = "$HOME/.local/state/tmux-watch" ] )
}
