#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped exports are how @test isolates each case

SCRIPT="$BATS_TEST_DIRNAME/tmux-obsidian-task-toggle"
US=$(printf '\037')

setup() {
  # The script sources $HOME/.dotfiles/bin/tmux-locklib (repo convention,
  # matched by tmux-repo-pr-fetch.bats) -- fake HOME and stock it with the
  # real tmux-locklib so this works the same on CI as it does here, without
  # depending on where the repo happens to be checked out.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.dotfiles/bin"
  cp "$BATS_TEST_DIRNAME/tmux-locklib" "$HOME/.dotfiles/bin/tmux-locklib"
}

# Builds a bin/tmux-obsidian-task-feed-format record: display, file, lineno,
# text, rawline. display/text are never read by the toggle script, so
# placeholder values are fine.
rec() {
  file="$1"; lineno="$2"; rawline="$3"
  printf '%s' "display${US}${file}${US}${lineno}${US}text${US}${rawline}"
}

@test "flips an open task to done, changing exactly the checkbox byte" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] request new computer #dotfiles')"
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$note")" = "- [x] request new computer #dotfiles" ]
}

@test "flips a done task back to open" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [x] request new computer #dotfiles\n' > "$note"
  run "$SCRIPT" "$(rec "$note" 2 '- [x] request new computer #dotfiles')"
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$note")" = "- [ ] request new computer #dotfiles" ]
}

@test "preserves the trailing space real notes carry after the tag" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] add overview #mission-control \n' > "$note"
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] add overview #mission-control ')"
  [ "$status" -eq 0 ]
  line=$(sed -n '2p' "$note")
  [ "$line" = "- [x] add overview #mission-control " ]
}

@test "flips a tab-indented sub-task" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n\t- [ ] indented sub-task\n' > "$note"
  run "$SCRIPT" "$(rec "$note" 2 "$(printf '\t- [ ] indented sub-task')")"
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$note")" = "$(printf '\t- [x] indented sub-task')" ]
}

@test "changes only one byte -- file size grows by zero" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  before=$(wc -c < "$note")
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] request new computer #dotfiles')"
  [ "$status" -eq 0 ]
  after=$(wc -c < "$note")
  [ "$before" -eq "$after" ]
}

@test "recovers from a stale line number by matching on content" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  # Record was read when the task was on line 2; three lines got inserted
  # above it in the meantime (e.g. Obsidian autosaved a new task).
  printf 'inserted 1\ninserted 2\ninserted 3\n## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] request new computer #dotfiles')"
  [ "$status" -eq 0 ]
  [ "$(sed -n '5p' "$note")" = "- [x] request new computer #dotfiles" ]
}

@test "refuses to write when the recorded line no longer matches anything in the file" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  before=$(cat "$note")
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] this text was edited in Obsidian meanwhile')"
  [ "$status" -eq 3 ]
  after=$(cat "$note")
  [ "$before" = "$after" ]
}

@test "preserves the file mode instead of dropping to mktemp's default 0600" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  chmod 644 "$note"
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] request new computer #dotfiles')"
  [ "$status" -eq 0 ]
  mode=$(ls -l "$note" | cut -c1-10)
  [ "$mode" = "-rw-r--r--" ]
}

@test "leaves a file with no trailing newline still without one" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles' > "$note"
  run "$SCRIPT" "$(rec "$note" 2 '- [ ] request new computer #dotfiles')"
  [ "$status" -eq 0 ]
  lastbyte=$(tail -c1 "$note" | wc -l | tr -d '[:space:]')
  [ "$lastbyte" = "0" ]
  [ "$(cat "$note")" = "$(printf '## Tasks\n- [x] request new computer #dotfiles')" ]
}

@test "reads the record from FZF_CURRENT_ITEM when no argv is given" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  export FZF_CURRENT_ITEM
  FZF_CURRENT_ITEM=$(rec "$note" 2 '- [ ] request new computer #dotfiles')
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$note")" = "- [x] request new computer #dotfiles" ]
}

@test "fails without writing when the file does not exist" {
  run "$SCRIPT" "$(rec "$BATS_TEST_TMPDIR/does-not-exist.md" 1 '- [ ] anything')"
  [ "$status" -ne 0 ]
}

@test "fails without writing when given no record and no FZF_CURRENT_ITEM" {
  unset FZF_CURRENT_ITEM
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "fails and does not write when another toggle holds the lock" {
  note="$BATS_TEST_TMPDIR/note.md"
  printf '## Tasks\n- [ ] request new computer #dotfiles\n' > "$note"
  before=$(cat "$note")

  lockdir=/tmp/tmux-obsidian-task-toggle.lock
  rm -rf "$lockdir"
  mkdir "$lockdir"
  sleep 30 &
  holder=$!
  echo "$holder" > "$lockdir/pid"

  run "$SCRIPT" "$(rec "$note" 2 '- [ ] request new computer #dotfiles')"
  [ "$status" -eq 2 ]
  after=$(cat "$note")
  [ "$before" = "$after" ]

  kill "$holder" 2>/dev/null
  rm -rf "$lockdir"
}
