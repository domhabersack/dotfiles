#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-sort-windows"

setup() {
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/bin"

  # Mock tmux: window state is "index TAB name TAB worktree_here" lines in
  # $MOCK_DIR/windows. move-window -s/-t relocates one window's index;
  # move-window -r compacts indices back to 1.. in current order -- exactly
  # what the script drives it through, so this is a faithful (if minimal)
  # re-implementation of the two operations actually under test.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
w="$MOCK_DIR/windows"
case "$1" in
  list-windows)
    fmt="$3"
    case "$fmt" in
    '#{window_index}	#{window_name}	#{?#{@worktree_here},1,0}')
      while IFS='	' read -r idx name wt; do
        if [ -n "$wt" ]; then flag=1; else flag=0; fi
        printf '%s\t%s\t%s\n' "$idx" "$name" "$flag"
      done < "$w"
      ;;
    '#{window_active} #{window_id}')
      # Not exercised by this suite's assertions -- one harmless line is
      # enough for the script's own `active=` computation to not error.
      first=$(head -1 "$w" | cut -f1)
      [ -n "$first" ] && printf '1 @%s\n' "$first"
      ;;
    '#{window_name}')
      cut -f2 "$w"
      ;;
    esac
    ;;
  move-window)
    if [ "$2" = "-r" ]; then
      tmp="$w.tmp"
      sort -t'	' -k1,1n "$w" | awk -F'\t' 'BEGIN{OFS="\t"; i=1} {print i,$2,$3; i++}' > "$tmp"
      mv "$tmp" "$w"
    else
      src=${3#:}
      dst=${5#:}
      tmp="$w.tmp"
      : > "$tmp"
      while IFS='	' read -r idx name wt; do
        [ "$idx" = "$src" ] && idx=$dst
        printf '%s\t%s\t%s\n' "$idx" "$name" "$wt" >> "$tmp"
      done < "$w"
      mv "$tmp" "$w"
    fi
    ;;
  select-window | run-shell) : ;;
  *) : ;;
  esac
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  : > "$MOCK_DIR/windows"
  PATH="$MOCK_DIR/bin:$PATH"
}

# add_window <name> [worktree_here-value]
add_window() {
  next=$(($(wc -l < "$MOCK_DIR/windows") + 1))
  printf '%s\t%s\t%s\n' "$next" "$1" "${2-}" >> "$MOCK_DIR/windows"
}

window_order() {
  sort -t'	' -k1,1n "$MOCK_DIR/windows" | cut -f2
}

worktree_flag_of_first_window() {
  sort -t'	' -k1,1n "$MOCK_DIR/windows" | head -1 | cut -f3
}

@test "a repo's own window sorts before its worktree window sharing its name" {
  # Adversarial creation order -- the worktree window exists FIRST, so a
  # naive slug-only sort (stable on ties) would leave it first too. Only a
  # sort that actually weighs @worktree_here corrects this.
  add_window szde-mucwin '⎇ '  # a linked worktree
  add_window szde-mucwin ''    # the repo's own checkout, created after
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(window_order)" = "$(printf 'szde-mucwin\nszde-mucwin\n')" ]
  # Confirm it's actually the non-worktree one first, not just two identical
  # names in an unverified order.
  [ "$(worktree_flag_of_first_window)" = "" ]
}

@test "unrelated windows still sort alphabetically by slug" {
  add_window zebra ''
  add_window apple ''
  add_window mango ''
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(window_order)" = "$(printf 'apple\nmango\nzebra\n')" ]
}

@test "a worktree window with no same-named main window sorts by name alone, not pushed to the back" {
  add_window banana ''
  add_window dom-agent-skills '⎇ '  # the only window with this name -- no tie
  add_window zucchini ''
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(window_order)" = "$(printf 'banana\ndom-agent-skills\nzucchini\n')" ]
}

@test "several worktree windows for the same repo all sort after its main window" {
  add_window sz-dossier-web '⎇ '
  add_window sz-dossier-web '⎇ '
  add_window sz-dossier-web ''  # the main checkout, created last
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(worktree_flag_of_first_window)" = "" ]
}

@test "re-running on an already tie-broken order changes nothing" {
  add_window szde-mucwin ''
  add_window szde-mucwin '⎇ '
  "$SCRIPT"
  before=$(window_order)
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(window_order)" = "$before" ]
}
