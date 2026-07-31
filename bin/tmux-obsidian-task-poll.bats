#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-obsidian-task-poll"

setup() {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export TMUX_OBSIDIAN_TASK_STAMP="$BATS_TEST_TMPDIR/stamp"
  export FZF_IDLE_TIME_MS=5000
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
}

@test "emits ignore when the daily notes folder has nothing in it" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "ignore" ]
}

@test "first call after a note appears emits reload-sync and writes the stamp" {
  printf '## Tasks\n- [ ] a task\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    "reload-sync("*")") ;;
    *) false ;;
  esac
  [ -s "$TMUX_OBSIDIAN_TASK_STAMP" ]
}

@test "a second call with no change emits ignore" {
  printf '## Tasks\n- [ ] a task\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  "$SCRIPT" >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "ignore" ]
}

@test "emits reload-sync again after the note content changes" {
  note="$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  printf '## Tasks\n- [ ] a task\n' > "$note"
  "$SCRIPT" >/dev/null
  printf '## Tasks\n- [x] a task\n' > "$note"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    "reload-sync("*")") ;;
    *) false ;;
  esac
}

@test "emits ignore when the fzf query box was typed in too recently" {
  printf '## Tasks\n- [ ] a task\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  export FZF_IDLE_TIME_MS=100
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "ignore" ]
}

@test "emits ignore when TMUX_OBSIDIAN_DAILY_DIR is unset" {
  unset TMUX_OBSIDIAN_DAILY_DIR
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "ignore" ]
}
