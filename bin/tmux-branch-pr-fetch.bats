#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-branch-pr-fetch"
REPO="bats-fixture-owner/bats-fixture-repo"
BRANCH="feat/foo"
# safe = tr '/' '_' over "<repo>/<branch>"
SAFE="bats-fixture-owner_bats-fixture-repo_feat_foo"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.dotfiles/bin" "$MOCK_DIR/bin"

  cp "$BATS_TEST_DIRNAME/tmux-locklib" "$HOME/.dotfiles/bin/tmux-locklib"

  # Stub the downstream re-render call: the real tmux-branch-pr talks to a live
  # tmux server, which doesn't exist here. Just prove it was reached.
  cat > "$HOME/.dotfiles/bin/tmux-branch-pr" <<EOF
#!/bin/sh
: > "$MOCK_DIR/rerendered"
EOF
  chmod +x "$HOME/.dotfiles/bin/tmux-branch-pr"

  # Mock gh: the only call is \`gh api graphql ...\`. Serves canned JSON this
  # test wrote into \$MOCK_DIR/graphql_response, or fails if a "gh_fail" marker
  # is present -- mirrors the real script's "expected, common" no-access / rate
  # limit / network-down case.
  cat > "$MOCK_DIR/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "api graphql")
    [ -f "$MOCK_DIR/gh_fail" ] && exit 1
    cat "$MOCK_DIR/graphql_response"
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/gh"
  # Default: a valid response with no matching PR.
  printf '%s' '{"data":{"repository":{"pullRequests":{"nodes":[]}}}}' > "$MOCK_DIR/graphql_response"

  PATH="$MOCK_DIR/bin:$PATH"
}

teardown() {
  rm -rf "/tmp/tmux-branch-pr-fetch-$SAFE.lock"
}

cache_field() {
  jq -r ".$1" "$HOME/.cache/tmux-branch-pr/$SAFE.json"
}

# Writes a full GraphQL response with a single node built from the JSON object
# passed as $1 (merged over sensible defaults, so a test only sets what it cares
# about).
write_response() {
  printf '%s' "$1" | jq -c '
    {
      number:1, additions:0, deletions:0, changedFiles:0,
      isDraft:false, reviewDecision:null, isCrossRepository:false,
      reviewThreads:{nodes:[]},
      commits:{nodes:[{commit:{statusCheckRollup:null}}]}
    } * . |
    {data:{repository:{pullRequests:{nodes:[.]}}}}
  ' > "$MOCK_DIR/graphql_response"
}

@test "skips the fetch entirely when a lock for the same repo+branch is already held" {
  mkdir -p "/tmp/tmux-branch-pr-fetch-$SAFE.lock"
  echo $$ > "/tmp/tmux-branch-pr-fetch-$SAFE.lock/pid"
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.cache/tmux-branch-pr/$SAFE.json" ]
}

@test "records status=error, has=false when the gh call fails" {
  : > "$MOCK_DIR/gh_fail"
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field status)" = "error" ]
  [ "$(cache_field has)" = "false" ]
}

@test "records has=false when no open PR matches the branch" {
  # default response has an empty nodes array
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field status)" = "ok" ]
  [ "$(cache_field has)" = "false" ]
}

@test "buckets every check-context conclusion/status/state correctly" {
  cat > "$MOCK_DIR/graphql_response" <<'EOF'
{"data":{"repository":{"pullRequests":{"nodes":[
  {
    "number":42,"additions":100,"deletions":5,"changedFiles":7,
    "isDraft":false,"reviewDecision":"APPROVED","isCrossRepository":false,
    "reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":true},{"isResolved":false}]},
    "commits":{"nodes":[{"commit":{"statusCheckRollup":{
      "state":"FAILURE",
      "contexts":{"totalCount":9,"nodes":[
        {"__typename":"CheckRun","conclusion":"SUCCESS","status":"COMPLETED"},
        {"__typename":"CheckRun","conclusion":"NEUTRAL","status":"COMPLETED"},
        {"__typename":"CheckRun","conclusion":"FAILURE","status":"COMPLETED"},
        {"__typename":"CheckRun","conclusion":"TIMED_OUT","status":"COMPLETED"},
        {"__typename":"CheckRun","conclusion":"SKIPPED","status":"COMPLETED"},
        {"__typename":"CheckRun","conclusion":null,"status":"IN_PROGRESS"},
        {"__typename":"StatusContext","state":"SUCCESS"},
        {"__typename":"StatusContext","state":"ERROR"},
        {"__typename":"StatusContext","state":"PENDING"}
      ]}
    }}}]}
  }
]}}}}
EOF
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field has)" = "true" ]
  [ "$(cache_field number)" = "42" ]
  [ "$(cache_field checks_state)" = "FAILURE" ]
  [ "$(cache_field checks_total)" = "9" ]
  # passed: SUCCESS + NEUTRAL (CheckRun) + SUCCESS (StatusContext) = 3
  [ "$(cache_field checks_passed)" = "3" ]
  # failed: FAILURE + TIMED_OUT (CheckRun) + ERROR (StatusContext) = 3
  [ "$(cache_field checks_failed)" = "3" ]
  # pending: not-COMPLETED CheckRun + PENDING StatusContext = 2
  [ "$(cache_field checks_pending)" = "2" ]
  # skipped: SKIPPED CheckRun = 1
  [ "$(cache_field checks_skipped)" = "1" ]
  # unresolved review conversations: 2 of 3 threads
  [ "$(cache_field unresolved)" = "2" ]
  [ "$(cache_field review)" = "APPROVED" ]
}

@test "treats a null statusCheckRollup as no checks (empty state, zero counts)" {
  write_response '{"number":7}'
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field has)" = "true" ]
  [ "$(cache_field checks_state)" = "" ]
  [ "$(cache_field checks_total)" = "0" ]
  [ "$(cache_field checks_passed)" = "0" ]
  [ "$(cache_field checks_failed)" = "0" ]
  [ "$(cache_field checks_pending)" = "0" ]
  [ "$(cache_field checks_skipped)" = "0" ]
}

@test "maps a null reviewDecision to an empty review string" {
  write_response '{"number":7, "reviewDecision":null}'
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field review)" = "" ]
}

@test "picks the same-repo PR over a fork PR sharing the branch name" {
  cat > "$MOCK_DIR/graphql_response" <<'EOF'
{"data":{"repository":{"pullRequests":{"nodes":[
  {"number":99,"additions":0,"deletions":0,"changedFiles":0,"isDraft":false,
   "reviewDecision":null,"isCrossRepository":true,
   "reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}},
  {"number":50,"additions":0,"deletions":0,"changedFiles":0,"isDraft":false,
   "reviewDecision":null,"isCrossRepository":false,
   "reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
]}}}}
EOF
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field has)" = "true" ]
  [ "$(cache_field number)" = "50" ]
}

@test "shows no PR when only a fork PR (cross-repository) matches the branch name" {
  write_response '{"number":99, "isCrossRepository":true}'
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ "$(cache_field has)" = "false" ]
}

@test "always re-renders via tmux-branch-pr after writing the cache" {
  run "$SCRIPT" "$REPO" "$BRANCH"
  [ "$status" -eq 0 ]
  [ -e "$MOCK_DIR/rerendered" ]
}
