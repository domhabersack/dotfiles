#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # bats: subshell-scoped exports are how @test isolates each case; literal backticks in expected strings need no expansion

SCRIPT="$BATS_TEST_DIRNAME/tmux-obsidian-task-list"

@test "prints a message and exits 0 when TMUX_OBSIDIAN_DAILY_DIR is unset" {
  unset TMUX_OBSIDIAN_DAILY_DIR
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "TMUX_OBSIDIAN_DAILY_DIR is not set" ]
}

@test "prints a message and exits 0 when the daily notes folder is missing" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/does-not-exist"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Daily notes folder not found: $TMUX_OBSIDIAN_DAILY_DIR" ]
}

@test "prints a friendly message when there are no open tasks" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-01 Wednesday.md" <<'EOF'
## Tasks
- [x] already done
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "No open tasks 🎉" ]
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
  printf '%s' "$output" | grep -qF -- "request new computer"
  case "$output" in
    *"why do we need a CoE?"*) false ;;
  esac
}

@test "excludes checked tasks and buckets untagged tasks as Uncategorized" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-17 Friday.md" <<'EOF'
## Tasks
- [x] ask platform support whether there should be an `EWI_SLACK_FAILURE_URL`
- [ ] unify Branch Protection rulesets across all EWI repositories
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$output" in
    *"EWI_SLACK_FAILURE_URL"*) false ;;
  esac
  printf '%s' "$output" | grep -qF -- "Uncategorized"
  printf '%s' "$output" | grep -qF -- "unify Branch Protection rulesets across all EWI repositories"
}

@test "extracts the project tag as a group label and strips it from the task text" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md" <<'EOF'
## Tasks
- [ ] check if `szm-internal-deployment` should be merged into an EWI project #ewi-deployment
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "ewi-deployment"
  printf '%s' "$output" | grep -qF -- 'check if `szm-internal-deployment` should be merged into an EWI project'
  case "$output" in
    *"#ewi-deployment"*) false ;;
  esac
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
  [ "$output" = "No open tasks 🎉" ]
}

@test "sorts groups alphabetically with Uncategorized last, and tasks oldest-first within a group" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-16 Thursday.md" <<'EOF'
## Tasks
- [ ] request new computer
EOF
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-17 Friday.md" <<'EOF'
## Tasks
- [ ] unify Branch Protection rulesets across all EWI repositories
EOF
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md" <<'EOF'
## Tasks
- [ ] check something #ewi-deployment
- [ ] file a follow-up #Zzz-later-project
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]

  ewi_line=$(printf '%s\n' "$output" | grep -n 'ewi-deployment' | cut -d: -f1)
  zzz_line=$(printf '%s\n' "$output" | grep -n 'Zzz-later-project' | cut -d: -f1)
  uncategorized_line=$(printf '%s\n' "$output" | grep -n 'Uncategorized' | cut -d: -f1)
  [ "$ewi_line" -lt "$zzz_line" ]
  [ "$zzz_line" -lt "$uncategorized_line" ]

  old_line=$(printf '%s\n' "$output" | grep -n '2026-07-16' | cut -d: -f1)
  new_line=$(printf '%s\n' "$output" | grep -n '2026-07-17' | cut -d: -f1)
  [ "$old_line" -lt "$new_line" ]
}

@test "renders a project group as a colorized header followed by its indented, checkbox-prefixed, date-prefixed task" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR" "$HOME/.dotfiles"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md" <<'EOF'
## Tasks
- [ ] check if `szm-internal-deployment` should be merged into an EWI project #ewi-deployment
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected_header=$(printf '\033[1;36mewi-deployment\033[0m')
  expected_line='[ ] 2026-07-20 check if `szm-internal-deployment` should be merged into an EWI project'
  [ "$(printf '%s\n' "$output" | sed -n '1p')" = "$expected_header" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "$expected_line" ]
}

@test "colors each project header per window-colors, falling back to the default when unmatched" {
  export TMUX_OBSIDIAN_DAILY_DIR="$BATS_TEST_TMPDIR/daily"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMUX_OBSIDIAN_DAILY_DIR" "$HOME/.dotfiles"
  cat > "$TMUX_OBSIDIAN_DAILY_DIR/2026-07-20 Monday.md" <<'EOF'
## Tasks
- [ ] check something #ewi-deployment
- [ ] file a follow-up #some-unlisted-project
EOF
  cat > "$HOME/.dotfiles/window-colors" <<'EOF'
[fg=colour6]
ewi-deployment
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  matched_header=$(printf '\033[38;5;6mewi-deployment\033[0m')
  fallback_header=$(printf '\033[1;36msome-unlisted-project\033[0m')
  printf '%s' "$output" | grep -qF -- "$matched_header"
  printf '%s' "$output" | grep -qF -- "$fallback_header"
}
