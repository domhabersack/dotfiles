#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-repo-pr-fetch"
REPO="bats-fixture-owner/bats-fixture-repo"
SAFE="bats-fixture-owner_bats-fixture-repo"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME/.dotfiles/bin" "$MOCK_DIR/bin"

  cp "$BATS_TEST_DIRNAME/tmux-locklib" "$HOME/.dotfiles/bin/tmux-locklib"

  # Stub the downstream re-render call: the real tmux-repo-pr talks to a
  # live tmux server, which doesn't exist here. Just prove it was reached.
  cat > "$HOME/.dotfiles/bin/tmux-repo-pr" <<EOF
#!/bin/sh
: > "$MOCK_DIR/rerendered"
EOF
  chmod +x "$HOME/.dotfiles/bin/tmux-repo-pr"

  # Mock gh: dispatches on the api path, serving canned JSON this test wrote
  # into \$MOCK_DIR, or failing if this test dropped a "*_fail" marker --
  # mirrors the real script's "expected, common" 403/404 case.
  cat > "$MOCK_DIR/bin/gh" <<'EOF'
#!/bin/sh
path=$2
case "$path" in
  *pulls*)
    [ -f "$MOCK_DIR/pulls_fail" ] && exit 1
    cat "$MOCK_DIR/pulls_response"
    ;;
  *dependabot/alerts*)
    if [ -f "$MOCK_DIR/alerts_disabled" ]; then
      echo "gh: Dependabot alerts are disabled for this repository. (HTTP 403)" >&2
      exit 1
    fi
    [ -f "$MOCK_DIR/alerts_fail" ] && exit 1
    cat "$MOCK_DIR/alerts_response"
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/bin/gh"
  printf '[]' > "$MOCK_DIR/pulls_response"
  printf '[]' > "$MOCK_DIR/alerts_response"

  PATH="$MOCK_DIR/bin:$PATH"
}

teardown() {
  rm -rf "/tmp/tmux-repo-pr-fetch-$SAFE.lock"
}

cache_field() {
  jq -r ".$1" "$HOME/.cache/tmux-repo-pr/$SAFE.json"
}

@test "skips the fetch entirely when a lock for the same repo is already held" {
  mkdir -p "/tmp/tmux-repo-pr-fetch-$SAFE.lock"
  echo $$ > "/tmp/tmux-repo-pr-fetch-$SAFE.lock/pid"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.cache/tmux-repo-pr/$SAFE.json" ]
}

@test "classifies PRs as bot by branch prefix or login, everything else human" {
  cat > "$MOCK_DIR/pulls_response" <<'EOF'
[
  {"head": {"ref": "feature/foo"}, "user": {"login": "domhabersack"}},
  {"head": {"ref": "dependabot/npm_and_yarn/foo-1.2.3"}, "user": {"login": "app/dependabot"}},
  {"head": {"ref": "renovate/bar"}, "user": {"login": "renovate-bot"}},
  {"head": {"ref": "fix/baz"}, "user": {"login": "renovate[bot]"}}
]
EOF
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cache_field pr_status)" = "ok" ]
  [ "$(cache_field pr_total)" = "4" ]
  [ "$(cache_field pr_human)" = "1" ]
  [ "$(cache_field pr_bot)" = "3" ]
}

@test "marks pr_status as error with zeroed counts when the PR fetch fails" {
  : > "$MOCK_DIR/pulls_fail"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cache_field pr_status)" = "error" ]
  [ "$(cache_field pr_total)" = "0" ]
  [ "$(cache_field pr_human)" = "0" ]
  [ "$(cache_field pr_bot)" = "0" ]
}

@test "dedups vulnerability alerts by package (highest severity wins), ignores non-open alerts" {
  cat > "$MOCK_DIR/alerts_response" <<'EOF'
[
  {"state": "open",  "dependency": {"package": {"ecosystem": "npm", "name": "foo"}}, "security_advisory": {"severity": "low"}},
  {"state": "open",  "dependency": {"package": {"ecosystem": "npm", "name": "foo"}}, "security_advisory": {"severity": "HIGH"}},
  {"state": "open",  "dependency": {"package": {"ecosystem": "pip", "name": "bar"}}, "security_advisory": {"severity": "critical"}},
  {"state": "fixed", "dependency": {"package": {"ecosystem": "pip", "name": "bar"}}, "security_advisory": {"severity": "critical"}},
  {"state": "open",  "dependency": {"package": {"ecosystem": "npm", "name": "baz"}}, "security_advisory": {}}
]
EOF
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cache_field vuln_status)" = "ok" ]
  # npm/foo dedups low+high -> high; pip/bar's "fixed" duplicate is dropped,
  # leaving one critical; npm/baz has no severity at all -> unknown.
  [ "$(cache_field vuln_total)" = "3" ]
  [ "$(cache_field vuln_critical)" = "1" ]
  [ "$(cache_field vuln_high)" = "1" ]
  [ "$(cache_field vuln_medium)" = "0" ]
  [ "$(cache_field vuln_low)" = "0" ]
  [ "$(cache_field vuln_unknown)" = "1" ]
}

@test "marks vuln_status as error with zeroed counts when the alerts fetch fails" {
  : > "$MOCK_DIR/alerts_fail"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cache_field vuln_status)" = "error" ]
  [ "$(cache_field vuln_total)" = "0" ]
  [ "$(cache_field vuln_critical)" = "0" ]
  [ "$(cache_field vuln_high)" = "0" ]
  [ "$(cache_field vuln_medium)" = "0" ]
  [ "$(cache_field vuln_low)" = "0" ]
  [ "$(cache_field vuln_unknown)" = "0" ]
}

@test "marks vuln_status as disabled (not error) when the API says alerts are turned off" {
  : > "$MOCK_DIR/alerts_disabled"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cache_field vuln_status)" = "disabled" ]
  [ "$(cache_field vuln_total)" = "0" ]
}

@test "leaves no stray stderr-capture file behind after a fetch" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  run find "$HOME/.cache/tmux-repo-pr" -name '*.err.*'
  [ -z "$output" ]
}

@test "a PR fetch failure doesn't blank the vulnerability half, and vice versa" {
  : > "$MOCK_DIR/pulls_fail"
  cat > "$MOCK_DIR/alerts_response" <<'EOF'
[{"state": "open", "dependency": {"package": {"ecosystem": "npm", "name": "foo"}}, "security_advisory": {"severity": "medium"}}]
EOF
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cache_field pr_status)" = "error" ]
  [ "$(cache_field vuln_status)" = "ok" ]
  [ "$(cache_field vuln_medium)" = "1" ]
}

@test "always re-renders via tmux-repo-pr after writing the cache" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -e "$MOCK_DIR/rerendered" ]
}
