#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # bats: subshell-scoped exports are how @test isolates each case; literal backticks/dollars in fixtures need no expansion

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-branch-pr"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.cache/tmux-branch-pr" "$HOME/.dotfiles/bin" "$MOCK_DIR/bin"

  # No-op stubs: tmux-branch-pr backgrounds a fetch on a cold/stale cache and
  # calls tmux-status-rows at the end; both must exist (so nohup/run don't
  # error) but neither needs to do real work here.
  for stub in tmux-branch-pr-fetch tmux-status-rows; do
    cat > "$HOME/.dotfiles/bin/$stub" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$HOME/.dotfiles/bin/$stub"
  done

  # Mock tmux: serves canned `list-windows` output from files this test writes
  # into $MOCK_DIR, and records every `set-window-option` call (the only way to
  # observe what the script decided to render) into $MOCK_DIR/captured. Only
  # shell builtins here: the "gh missing" test runs with PATH stripped to just
  # this directory, so it must serve list-windows on its own.
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
    # $1=set-window-option $2=-t $3=wid $4=@branch_pr $5=value
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

# A git repo on branch `main` with a GitHub origin, at $1.
make_repo() {
  git init -q -b main "$1"
  git -C "$1" remote add origin https://github.com/example-owner/example-repo.git
}

# write_cache writes the per-repo+branch cache. Args after the repo/branch are
# jq object fields as a single JSON body.
write_cache() {
  # write_cache <repo> <branch> <json-body>
  safe=$(printf '%s/%s' "$1" "$2" | tr '/' '_')
  printf '%s\n' "$3" > "$HOME/.cache/tmux-branch-pr/$safe.json"
}

@test "clears every window's @branch_pr when gh is not installed" {
  printf '@1\n@2\n' > "$MOCK_DIR/windows_ids"
  PATH="$MOCK_DIR/bin" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
  [ "$(captured_for '@2')" = "" ]
  [ "$(wc -l < "$MOCK_DIR/captured" | tr -d ' ')" -eq 2 ]
}

@test "only renders the attached session's active window, skipping the rest" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/active"
  add_window 1 0 @2 "$BATS_TEST_TMPDIR/inactive"
  add_window 0 1 @3 "$BATS_TEST_TMPDIR/detached"
  mkdir -p "$BATS_TEST_TMPDIR/active" "$BATS_TEST_TMPDIR/inactive" "$BATS_TEST_TMPDIR/detached"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF '@1' "$MOCK_DIR/captured"
  run ! grep -qF '@2' "$MOCK_DIR/captured"
  run ! grep -qF '@3' "$MOCK_DIR/captured"
}

@test "clears @branch_pr for a window whose path isn't inside a git repo" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/plain-dir"
  mkdir -p "$BATS_TEST_TMPDIR/plain-dir"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "clears @branch_pr for a git repo with no origin remote" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/no-origin"
  git init -q "$BATS_TEST_TMPDIR/no-origin"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "shows nothing (no flashed placeholder row) when no cache exists yet" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "renders nothing when the branch has no open PR (has=false)" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main '{"status":"ok","has":false,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "renders nothing when the fetch errored (status=error)" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main '{"status":"error","has":false,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(captured_for '@1')" = "" ]
}

@test "renders number, diff size, passing checks, approval, and unresolved count" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":42,"additions":120,"deletions":30,"changed":3,"draft":false,"review":"APPROVED","checks_state":"SUCCESS","checks_total":4,"checks_skipped":0,"unresolved":2,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf 'PR ##42 · 3 files · #[fg=colour2]+120#[default] #[fg=colour1]-30#[default] · #[fg=colour2]all checks have passed#[default] · #[fg=colour2]approved#[default] · #[fg=colour3]2 unresolved#[default]')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "singularizes 'file' and omits the unresolved segment at zero" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":7,"additions":5,"deletions":0,"changed":1,"draft":false,"review":"","checks_state":"SUCCESS","checks_total":1,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf 'PR ##7 · 1 file · #[fg=colour2]+5#[default] #[fg=colour1]-0#[default] · #[fg=colour2]all checks have passed#[default]')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "shows a red failing-checks marker" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"","checks_state":"FAILURE","checks_total":3,"checks_failed":2,"checks_pending":0,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour1]2 checks failed#[default]"*) : ;;
    *) false ;;
  esac
}

@test "appends the pending count to a failing rollup, and singularizes 'check'" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"","checks_state":"FAILURE","checks_total":3,"checks_failed":1,"checks_pending":2,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour1]1 check failed#[default] #[fg=colour3]· 2 pending#[default]"*) : ;;
    *) false ;;
  esac
}

@test "shows a yellow pending-checks marker" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"","checks_state":"PENDING","checks_total":2,"checks_failed":0,"checks_pending":2,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour3]2 checks pending#[default]"*) : ;;
    *) false ;;
  esac
}

@test "shows 'draft' instead of a review decision for a draft PR" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":true,"review":"APPROVED","checks_state":"SUCCESS","checks_total":1,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  out="$(captured_for '@1')"
  case "$out" in *"#[fg=colour244]draft#[default]"*) : ;; *) false ;; esac
  case "$out" in *approved*) false ;; *) : ;; esac
}

@test "shows a red 'changes requested' segment" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"CHANGES_REQUESTED","checks_state":"SUCCESS","checks_total":1,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour1]changes requested#[default]"*) : ;;
    *) false ;;
  esac
}

@test "omits the review segment for REVIEW_REQUIRED (nobody has weighed in)" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"REVIEW_REQUIRED","checks_state":"SUCCESS","checks_total":3,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  expected=$(printf 'PR ##9 · 1 file · #[fg=colour2]+1#[default] #[fg=colour1]-1#[default] · #[fg=colour2]all checks have passed#[default]')
  [ "$(captured_for '@1')" = "$expected" ]
}

@test "shows 'no checks' when the head commit has no checks configured" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"","checks_state":"","checks_total":0,"checks_skipped":0,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour244]no checks#[default]"*) : ;;
    *) false ;;
  esac
}

@test "annotates skipped checks alongside an all-passed rollup" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"","checks_state":"SUCCESS","checks_total":3,"checks_skipped":1,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour2]all checks have passed#[default] #[fg=colour244](1 skipped)#[default]"*) : ;;
    *) false ;;
  esac
}

@test "reports 'all checks skipped' when every check was skipped" {
  add_window 1 1 @1 "$BATS_TEST_TMPDIR/repo"
  make_repo "$BATS_TEST_TMPDIR/repo"
  write_cache example-owner/example-repo main \
    '{"status":"ok","has":true,"number":9,"additions":1,"deletions":1,"changed":1,"draft":false,"review":"","checks_state":"SUCCESS","checks_total":2,"checks_skipped":2,"unresolved":0,"fetched_at":0}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  case "$(captured_for '@1')" in
    *"#[fg=colour244]all checks skipped#[default]"*) : ;;
    *) false ;;
  esac
}
