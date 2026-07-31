#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case
#
# Only the fzf-absent fallback path is testable here: fzf isn't installed
# on the CI runner, and driving a real interactive fzf session isn't
# something bats can do. That's deliberate -- the picker is kept thin (fzf
# resolution + a fallback + building one command line) specifically so the
# untestable part is as small as possible; the pieces it wires together
# (bin/tmux-obsidian-task-list, -feed, -toggle, -poll) each have their own
# bats coverage. The fzf-present path is hand-verified per the design doc.

SCRIPT="$BATS_TEST_DIRNAME/tmux-obsidian-task-picker"

@test "prints a message and exits 0 when TMUX_OBSIDIAN_DAILY_DIR is unset" {
  unset TMUX_OBSIDIAN_DAILY_DIR
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "TMUX_OBSIDIAN_DAILY_DIR is not set" ]
}

@test "falls back to the read-only list when fzf is not on PATH and not at ~/.fzf/bin/fzf" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export HOME="$BATS_TEST_TMPDIR/home"
  export PATH="/usr/bin:/bin"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR" "$HOME"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "request new computer"
  printf '%s' "$output" | grep -qF -- "dotfiles"
}

@test "the fallback still shows the friendly empty-list message" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export HOME="$BATS_TEST_TMPDIR/home"
  export PATH="/usr/bin:/bin"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR" "$HOME"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "No open tasks"
}
