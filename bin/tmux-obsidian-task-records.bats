#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # bats: subshell-scoped exports are how @test isolates each case; literal backticks in expected strings need no expansion

SCRIPT="$BATS_TEST_DIRNAME/tmux-obsidian-task-records"
US=$(printf '\037')

@test "silently exits 0 with no output when TMUX_OBSIDIAN_DAILY_DIR is unset" {
  unset TMUX_OBSIDIAN_DAILY_DIR
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "silently exits 0 with no output when the daily notes folder is missing" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/does-not-exist"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "silently exits 0 with no output when there are no daily notes" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "emits nine US-delimited fields for an open task" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print NF}')" -eq 9 ]
}

@test "extracts sortkey, project, date, text and state=\" \" for an open tagged task" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  sortkey=$(printf '%s' "$output" | awk -F"$US" '{print $1}')
  project=$(printf '%s' "$output" | awk -F"$US" '{print $2}')
  date=$(printf '%s' "$output" | awk -F"$US" '{print $3}')
  text=$(printf '%s' "$output" | awk -F"$US" '{print $4}')
  state=$(printf '%s' "$output" | awk -F"$US" '{print $5}')
  [ "$sortkey" = "dotfiles" ]
  [ "$project" = "dotfiles" ]
  [ "$date" = "2026-07-20" ]
  [ "$text" = "request new computer" ]
  [ "$state" = " " ]
}

@test "includes done tasks with state=x, unlike the read-only renderer" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [x] already done #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $5}')" = "x" ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $4}')" = "already done" ]
}

@test "untagged tasks bucket as Uncategorized with sortkey ~" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] book flights\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $1}')" = "~" ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $2}')" = "Uncategorized" ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $4}')" = "book flights" ]
}

@test "ignores checkbox lines outside the Tasks section" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-16 Thursday.md" <<'EOF'
## Tasks
- [ ] request new computer
## Meetings
### Tech Lead Weekly
- [ ] why do we need a CoE?
## Notes
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  printf '%s' "$output" | grep -qF -- "request new computer"
  case "$output" in
    *"why do we need a CoE?"*) false ;;
  esac
}

@test "reports lineno as the 1-based line of the task within its note, counting content above Tasks" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf 'preamble line\nanother line\n## Tasks\n- [ ] the task #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $8}')" = "4" ]
}

@test "file field is the note's absolute path" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [ ] the task #dotfiles\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk -F"$US" '{print $7}')" = "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md" ]
}

@test "rawline is byte-identical to the source line, including trailing space and tab indentation" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n\t- [ ] indented task #dotfiles \n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  rawline=$(printf '%s' "$output" | cut -d "$US" -f9)
  [ "$rawline" = "$(printf '\t- [ ] indented task #dotfiles ')" ]
}

@test "colour is the window-colors 256-colour number for the project, or 0 when unlisted" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR" "$HOME/.dotfiles"
  printf '## Tasks\n- [ ] a #listed\n- [ ] b #unlisted\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md"
  cat > "$HOME/.dotfiles/window-colors" <<'EOF'
[fg=colour6]
listed
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  listed_colour=$(printf '%s\n' "$output" | awk -F"$US" '$2 == "listed" {print $6}')
  unlisted_colour=$(printf '%s\n' "$output" | awk -F"$US" '$2 == "unlisted" {print $6}')
  [ "$listed_colour" = "6" ]
  [ "$unlisted_colour" = "0" ]
}

@test "orders by project (Uncategorized last), then state (open before done), then date, then line" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  printf '## Tasks\n- [x] old done #alpha\n- [ ] old open #alpha\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-16 Thursday.md"
  printf '## Tasks\n- [ ] new open #alpha\n- [ ] untagged\n' > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-17 Friday.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  texts=$(printf '%s\n' "$output" | awk -F"$US" '{print $4}')
  expected=$(printf 'old open\nnew open\nold done\nuntagged')
  [ "$texts" = "$expected" ]
}

@test "silently skips a daily note that has no Tasks heading at all" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-02 Thursday.md" <<'EOF'
## Meetings
### Some sync
- [ ] not a real task, just meeting notes shorthand
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
