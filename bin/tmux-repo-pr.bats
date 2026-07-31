#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # bats: subshell-scoped exports are how @test isolates each case; literal backticks/dollars in fixtures need no expansion

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-repo-pr"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.cache/tmux-repo-pr" "$HOME/.dotfiles/bin" "$MOCK_DIR/bin"

  # No-op stub: tmux-repo-pr backgrounds a fetch on a cold/stale cache: it
  # must exist (so nohup doesn't error) but never needs to do real work here.
  cat > "$HOME/.dotfiles/bin/tmux-repo-pr-fetch" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$HOME/.dotfiles/bin/tmux-repo-pr-fetch"

  # Mock tmux: serves canned `list-windows` output from files this test
  # writes into $MOCK_DIR, and records every `set-window-option` call (the
  # only way to observe what the script decided to render) into $MOCK_DIR/captured.
  # No `cat`/other external tools here (only shell builtins): the "gh
  # missing" test runs this mock with a PATH stripped down to just this
  # directory, so it must be able to serve list-windows on its own.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  list-windows)
    case "$*" in
      *session_attached*) file="$MOCK_DIR/windows_full" ;;
      *)                   file="$MOCK_DIR/windows_ids" ;;
    esac
    while IFS= read -r ln; do printf '%s\n' "$ln"; done < "$file"
    ;;
  set-window-option)
    # $1=set-window-option $2=-t $3=wid $4=@repo_pr $5=value
    printf '%s\t%s\n' "$3" "$5" >> "$MOCK_DIR/captured"
    ;;
  *) : ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  : > "$MOCK_DIR/windows_full"
  : > "$MOCK_DIR/windows_ids"
  : > "$MOCK_DIR/captured"

  PATH="$MOCK_DIR/bin:$PATH"
}

# One `list-windows -a -F '#{session_attached} #{window_active} #{window_id} #{pane_current_path}'` row.
add_window() {
  printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> "$MOCK_DIR/windows_full"
}

captured_for() {
  grep "^$1	" "$MOCK_DIR/captured" | cut -f2-
}

write_cache() {
  # write_cache <repo> <pr_status> <pr_total> <pr_human> <pr_bot> <vuln_status> <vuln_total> <critical> <high> <medium> <low> <unknown>
  safe=$(printf '%s' "$1" | tr '/' '_')
  jq -n \
    --arg pr_status "$2" --argjson pr_total "$3" --argjson pr_human "$4" --argjson pr_bot "$5" \
    --arg vuln_status "$6" --argjson vuln_total "$7" --argjson critical "$8" --argjson high "$9" \
    '{pr_status: $pr_status, pr_total: $pr_total, pr_human: $pr_human, pr_bot: $pr_bot,
      vuln_status: $vuln_status, vuln_total: $vuln_total, vuln_critical: $critical, vuln_high: $high,
      vuln_medium: 0, vuln_low: 0, vuln_unknown: 0, fetched_at: 0}' \
    > "$HOME/.cache/tmux-repo-pr/$safe.json"
}

@test "clears every window's @repo_pr when gh is not installed" {
  printf '@1\n@2\n' > "$MOCK_DIR/windows_ids"
  PATH="$MOCK_DIR/bin" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
  [ "$(captured_for '@2')" = "" ]
  [ "$(wc -l < "$MOCK_DIR/captured" | tr -d ' ')" -eq 2 ]
}

@test "only renders the attached session's active window, skipping the rest" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/not-a-repo-active"
  add_window 1 0 @2 "$BATS_TEST_TMPDIR/not-a-repo-inactive"
  add_window 0 1 @3 "$BATS_TEST_TMPDIR/not-a-repo-detached"
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo-active" "$BATS_TEST_TMPDIR/not-a-repo-inactive" "$BATS_TEST_TMPDIR/not-a-repo-detached"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF '@1' "$MOCK_DIR/captured"
  run ! grep -qF '@2' "$MOCK_DIR/captured"
  run ! grep -qF '@3' "$MOCK_DIR/captured"
}

@test "clears @repo_pr for a window whose path isn't inside a git repo" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/plain-dir"
  mkdir -p "$BATS_TEST_TMPDIR/plain-dir"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "clears @repo_pr for a git repo with no origin remote" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/no-origin"
  git init -q "$BATS_TEST_TMPDIR/no-origin"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "clears @repo_pr when the origin remote doesn't parse into an owner/repo" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/bare-remote"
  git init -q "$BATS_TEST_TMPDIR/bare-remote"
  git -C "$BATS_TEST_TMPDIR/bare-remote" remote add origin myrepo
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "shows a loading indicator with the owner/repo parsed from an https origin, when no cache exists yet" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/https-repo"
  git init -q "$BATS_TEST_TMPDIR/https-repo"
  git -C "$BATS_TEST_TMPDIR/https-repo" remote add origin https://github.com/example-owner/example-repo.git
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "$(printf '#[fg=colour238]example-repo #[fg=colour4]…#[default]')" ]
}

@test "parses an ssh-shorthand origin the same way as https" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/ssh-repo"
  git init -q "$BATS_TEST_TMPDIR/ssh-repo"
  git -C "$BATS_TEST_TMPDIR/ssh-repo" remote add origin git@github.com:example-owner/example-repo.git
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "$(printf '#[fg=colour238]example-repo #[fg=colour4]…#[default]')" ]
}

@test "renders PR count with human/bot split alongside a clean vulnerability scan" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo ok 1 1 0 ok 0 0 0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf '#[fg=colour238]example-repo#[default] · #[bold]1 PR#[nobold] (#[fg=colour6]1#[default] human, #[fg=colour6]0#[default] bot) · no known vulnerabilities')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "renders a plain 'no PRs' segment without the human/bot split when there are no open PRs" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo ok 0 0 0 ok 0 0 0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf '#[fg=colour238]example-repo#[default] · no PRs · no known vulnerabilities')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "omits the PR segment when the PR half errored, keeping the vulnerability segment" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo error 0 0 0 ok 0 0 0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf '#[fg=colour238]example-repo#[default] · no known vulnerabilities')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "renders severity-ordered, colored vulnerability counts and skips zero buckets" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo error 0 0 0 ok 3 2 1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf '#[fg=colour238]example-repo#[default] · #[bold]3 vulnerabilities#[nobold] (#[fg=colour196]2 critical#[default], #[fg=colour208]1 high#[default])')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "warns that Dependabot is not enabled instead of showing a clean scan" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo error 0 0 0 disabled 0 0 0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf '#[fg=colour238]example-repo#[default] · #[fg=colour214]dependabot not enabled#[default]')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "clears @repo_pr when both PR and vulnerability halves errored" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo error 0 0 0 error 0 0 0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "pluralizes PR and vulnerability labels for counts other than one" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  git init -q "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" remote add origin https://github.com/example-owner/example-repo.git
  write_cache example-owner/example-repo ok 2 1 1 ok 1 0 1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  output_val="$(captured_for '@1')"
  case "$output_val" in
    *"2 PRs#[nobold]"*) : ;;
    *) false ;;
  esac
  case "$output_val" in
    *"1 vulnerability#[nobold]"*) : ;;
    *) false ;;
  esac
}
