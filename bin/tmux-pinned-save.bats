#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-pinned-save"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$HOME" "$MOCK_DIR/bin"

  # Mock tmux: serves canned `list-windows -a -F <fmt>` output. The script
  # filters inside the format string, so the mock has to evaluate the one format
  # it is given against each window rather than just replaying a fixture — that
  # is precisely the behaviour under test.
  cat > "$MOCK_DIR/bin/tmux" <<'EOF'
#!/bin/sh
[ "$1" = "list-windows" ] || exit 0
# windows file holds "<pinned>\t<session>\t<window>" per line
while IFS='	' read -r pinned sess win; do
  if [ "$pinned" = "1" ]; then
    printf '%s\t%s\n' "$sess" "$win"
  else
    printf '\n'
  fi
done < "$MOCK_DIR/windows"
EOF
  chmod +x "$MOCK_DIR/bin/tmux"
  : > "$MOCK_DIR/windows"

  PATH="$MOCK_DIR/bin:$PATH"
  STATE="$HOME/.tmux/resurrect/pinned"
}

# add_window <pinned> <session> <window-name>
add_window() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MOCK_DIR/windows"
}

@test "writes one session-TAB-name line per pinned window" {
  add_window 1 work notes
  add_window 0 work code
  add_window 1 play games
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE")" = "$(printf 'work\tnotes\nplay\tgames')" ]
}

@test "creates the state directory when it does not exist yet" {
  [ ! -d "$HOME/.tmux/resurrect" ]
  add_window 1 work notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
}

@test "writes an empty file, and does not fail, when nothing is pinned" {
  add_window 0 work code
  add_window 0 work notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
  [ ! -s "$STATE" ]
}

@test "preserves window names containing spaces" {
  add_window 1 work "my long name"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE")" = "$(printf 'work\tmy long name')" ]
}

@test "overwrites a previous save rather than appending" {
  add_window 1 work notes
  run "$SCRIPT"
  : > "$MOCK_DIR/windows"
  add_window 1 work code
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE")" = "$(printf 'work\tcode')" ]
}

@test "leaves no temp file behind" {
  add_window 1 work notes
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$STATE.tmp" ]
}
