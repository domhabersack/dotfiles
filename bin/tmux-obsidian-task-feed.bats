#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-obsidian-task-feed"
US=$(printf '\037')
ESC=$(printf '\033')

@test "shows nothing and exits 0 when there are no daily notes" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "shows done tasks by default, dimmed" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [x] already done #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  display=$(printf '%s' "$output" | cut -d "$US" -f1)
  case "$display" in
    "${ESC}[2m"*"already done"*"${ESC}[0m") ;;
    *) false ;;
  esac
}

@test "hides done tasks when TMUX_OBSIDIAN_TASK_HIDEDONE points at an existing file" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] open task #dotfiles\n- [x] done task #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  export TMUX_OBSIDIAN_TASK_HIDEDONE="$BATS_TEST_TMPDIR/hidedone"
  : > "$TMUX_OBSIDIAN_TASK_HIDEDONE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  printf '%s' "$output" | grep -qF -- "open task"
  case "$output" in
    *"done task"*) false ;;
  esac
}

@test "shows done tasks again when TMUX_OBSIDIAN_TASK_HIDEDONE points at a missing file" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] open task #dotfiles\n- [x] done task #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  export TMUX_OBSIDIAN_TASK_HIDEDONE="$BATS_TEST_TMPDIR/does-not-exist"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "display field carries the checkbox prefix and the project's color escape for an open task" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR" "$HOME/.dotfiles"
  printf '## Tasks\n- [ ] check something #ewi-deployment\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  cat > "$HOME/.dotfiles/window-colors" <<'EOF'
[fg=colour6]
ewi-deployment
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  display=$(printf '%s' "$output" | cut -d "$US" -f1)
  case "$display" in
    "[ ] ${ESC}[38;5;6m"*"${ESC}[0m"*"check something"*) ;;
    *) false ;;
  esac
}

@test "pads the project column to a constant width across rows" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] short one #a\n- [ ] long one #a-much-longer-project\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Padded project text sits between the color-on and color-off escapes;
  # its printable width (spaces included) must be identical for both rows.
  field_between_color_codes() {
    awk -v esc="$ESC" '{
      s = $0
      sub("^\\[ \\] " esc "\\[38;5;[0-9]+m", "", s)   # drop the checkbox + color-on prefix
      i = index(s, esc "[0m")                          # find the color-off code
      print substr(s, 1, i - 1)
    }'
  }
  short_field=$(printf '%s\n' "$output" | grep 'short one' | field_between_color_codes)
  long_field=$(printf '%s\n' "$output" | grep 'long one' | field_between_color_codes)
  [ "$long_field" = "a-much-longer-project" ]
  [ "${#short_field}" -eq "${#long_field}" ]
  case "$short_field" in
    "a "*) ;;
    *) false ;;
  esac
}

@test "hidden fields carry file, lineno, tag-stripped text and the byte-exact rawline" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  note="$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  printf '## Tasks\n- [ ] check something #dotfiles \n' > "$note"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | cut -d "$US" -f2)" = "$note" ]
  [ "$(printf '%s' "$output" | cut -d "$US" -f3)" = "2" ]
  [ "$(printf '%s' "$output" | cut -d "$US" -f4)" = "check something" ]
  [ "$(printf '%s' "$output" | cut -d "$US" -f5)" = "- [ ] check something #dotfiles " ]
}
