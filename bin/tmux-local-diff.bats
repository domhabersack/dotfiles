#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats: subshell-scoped state is how @test isolates each case

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/tmux-local-diff"

# A throwaway git repo per test, with identity passed inline so the suite never
# depends on (or mutates) the runner's global git config. core.excludesFile is
# pinned to an empty file for the same reason: the runner's own global ignore
# rules must not reach into these repos (one case overrides it deliberately).
GIT() {
  git -C "$REPO" \
    -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    -c "core.excludesFile=$BATS_TEST_TMPDIR/empty-excludes" "$@"
}

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  : > "$BATS_TEST_TMPDIR/empty-excludes"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig-global"
  printf '[core]\n\texcludesFile = %s/empty-excludes\n' "$BATS_TEST_TMPDIR" \
    > "$GIT_CONFIG_GLOBAL"
}

# A repo whose trunk is $1 (default main) with one committed file — the shape
# almost every case below starts from.
init_repo() {
  git init -q "$REPO"
  GIT symbolic-ref HEAD "refs/heads/${1:-main}"
  printf 'base\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m init
}

# The counts without the tmux style tags, so assertions read as the user sees
# them: "4 files · +120 -30".
plain() { printf '%s' "$1" | sed -e 's/#\[[^]]*\]//g'; }

# Assert the script reports exactly $1 for the repo (or for $2, a path inside it).
assert_summary() {
  run "$SCRIPT" "${2:-$REPO}"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "$1" ]
}


################################
# Nothing to report            #
################################

@test "prints nothing outside a git work tree" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prints nothing on a clean checkout of the trunk" {
  init_repo
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prints nothing when the repo has no local trunk ref" {
  git init -q "$REPO"
  GIT symbolic-ref HEAD refs/heads/experiment
  printf 'base\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m init
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores a remote-tracking main with no local branch" {
  git init -q "$REPO"
  GIT symbolic-ref HEAD refs/heads/experiment
  printf 'base\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m init
  GIT update-ref refs/remotes/origin/main HEAD
  printf 'base\nchanged\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


################################
# What counts as working state #
################################

@test "counts committed work on a feature branch" {
  init_repo
  GIT checkout -q -b feature
  printf 'base\nadded\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m work
  assert_summary "1 file · +1 -0"
}

@test "counts staged and unstaged work alongside commits" {
  init_repo
  GIT checkout -q -b feature
  printf 'committed\n' > "$REPO/committed"
  GIT add committed
  GIT commit -q -m work
  printf 'staged\n' > "$REPO/staged"
  GIT add staged
  printf 'base\nunstaged\n' > "$REPO/tracked"
  assert_summary "3 files · +3 -0"
}

@test "counts uncommitted work while sitting on the trunk itself" {
  init_repo
  printf 'base\nmore\n' > "$REPO/tracked"
  assert_summary "1 file · +1 -0"
}

@test "counts deletions" {
  init_repo
  GIT checkout -q -b feature
  GIT rm -q tracked
  assert_summary "1 file · +0 -1"
}

@test "counts untracked files as pure additions" {
  init_repo
  printf 'one\ntwo\nthree\n' > "$REPO/new"
  assert_summary "1 file · +3 -0"
}

@test "counts an untracked file whose last line has no trailing newline" {
  init_repo
  printf 'one\ntwo' > "$REPO/new"
  assert_summary "1 file · +2 -0"
}

@test "counts untracked files outside the directory it is given" {
  init_repo
  mkdir -p "$REPO/sub"
  printf 'in-sub\n' > "$REPO/sub/keep"
  printf 'at-root\n' > "$REPO/at-root"
  assert_summary "2 files · +2 -0" "$REPO/sub"
}

@test "counts a rename as a deletion plus an addition, not as zero" {
  init_repo
  printf 'a\nb\nc\nd\ne\n' > "$REPO/original"
  GIT add original
  GIT commit -q -m add-original
  GIT checkout -q -b feature
  GIT mv original renamed
  assert_summary "2 files · +5 -5"
}

@test "pluralises the file count" {
  init_repo
  printf 'one\n' > "$REPO/a"
  printf 'two\n' > "$REPO/b"
  assert_summary "2 files · +2 -0"
}

@test "defaults to the current directory when given no argument" {
  init_repo
  printf 'base\nadded\n' > "$REPO/tracked"
  run env -C "$REPO" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
}


################################
# Which ref it measures against#
################################

@test "compares against the trunk ref itself, not the merge base" {
  init_repo
  GIT checkout -q -b feature
  printf 'base\nfeature\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m feature-work
  # main moves ahead with a line the branch doesn't have: a merge-base diff
  # would ignore it, a trunk-tip diff reports it as a deletion.
  GIT checkout -q main
  printf 'base\nmain-only\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m main-work
  GIT checkout -q feature
  assert_summary "1 file · +1 -1"
}

@test "shrinks back to the branch's own work after a rebase onto main" {
  init_repo
  GIT checkout -q -b feature
  printf 'feature\n' > "$REPO/feature-file"
  GIT add feature-file
  GIT commit -q -m feature-work
  GIT checkout -q main
  printf 'base\nmain-only\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m main-work
  GIT checkout -q feature
  assert_summary "2 files · +1 -1"
  GIT rebase -q main
  assert_summary "1 file · +1 -0"
}

@test "resolves the trunk as a branch even when a tag shares its name" {
  init_repo
  GIT tag anchor HEAD
  GIT checkout -q -b feature
  # main advances past the anchor, so branch and tag disagree.
  GIT checkout -q main
  printf 'base\nmainA\nmainB\nmainC\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m main-work
  GIT checkout -q feature
  printf 'base\nfeat\n' > "$REPO/tracked"
  # A TAG named "main" pointing back at the original commit. Git's own
  # disambiguation prefers refs/tags over refs/heads, so a bare "main" here
  # would measure against the tag and report "+1 -0".
  GIT tag main anchor
  assert_summary "1 file · +1 -3"
}

@test "is not confused by a file named like the trunk" {
  init_repo
  GIT checkout -q -b feature
  printf 'a\nb\n' > "$REPO/main"
  assert_summary "1 file · +2 -0"
}

@test "is not confused by a path that collides with the full trunk ref" {
  init_repo
  GIT checkout -q -b feature
  # A file at refs/heads/main makes the ref argument ambiguous with a path;
  # without the "--" separator git aborts with "both revision and filename".
  mkdir -p "$REPO/refs/heads"
  printf 'a\nb\n' > "$REPO/refs/heads/main"
  assert_summary "1 file · +2 -0"
}

@test "falls back to master when there is no main" {
  init_repo master
  GIT checkout -q -b feature
  printf 'base\nadded\n' > "$REPO/tracked"
  assert_summary "1 file · +1 -0"
}

@test "prefers main over master when both exist" {
  init_repo
  GIT branch master
  GIT checkout -q -b feature
  # Move master away so a master-based comparison would give a different count.
  printf 'base\nmaster-only\n' > "$REPO/tracked"
  GIT add tracked
  GIT commit -q -m master-work
  GIT branch -f master feature
  printf 'base\nmaster-only\nmore\n' > "$REPO/tracked"
  # vs main: two added lines. vs master: one.
  assert_summary "1 file · +2 -0"
}


################################
# Ignore rules                 #
################################

@test "ignores untracked files excluded by .gitignore" {
  init_repo
  printf 'build/\n' > "$REPO/.gitignore"
  GIT add .gitignore
  GIT commit -q -m ignore
  mkdir -p "$REPO/build"
  printf 'junk\n' > "$REPO/build/out"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores changes to files that are TRACKED but match an ignore rule" {
  init_repo
  # node_modules committed first, .gitignore added afterwards — ignore rules
  # do not apply to already-tracked files, so only an explicit check-ignore
  # pass can exclude these.
  mkdir -p "$REPO/node_modules/pkg"
  printf 'a\nb\nc\n' > "$REPO/node_modules/pkg/dep.js"
  GIT add node_modules
  GIT commit -q -m vendored
  printf 'node_modules/\n' > "$REPO/.gitignore"
  GIT add .gitignore
  GIT commit -q -m ignore
  GIT checkout -q -b feature
  printf 'a\nb\nc\nCHANGED\nMORE\n' > "$REPO/node_modules/pkg/dep.js"
  printf 'new\n' > "$REPO/node_modules/pkg/added.js"
  printf 'base\nreal work\n' > "$REPO/tracked"
  # Without the filter this would be "3 files · +4 -0".
  assert_summary "1 file · +1 -0"
}

@test "honors the global excludesFile for tracked and untracked alike" {
  init_repo
  mkdir -p "$REPO/globaljunk"
  printf 'a\nb\nc\n' > "$REPO/globaljunk/x"
  GIT add globaljunk
  GIT commit -q -m vendored
  GIT checkout -q -b feature
  printf 'a\nb\nc\nCHANGED\n' > "$REPO/globaljunk/x"
  printf 'new\nnew2\n' > "$REPO/globaljunk/untracked"
  printf 'base\nreal work\n' > "$REPO/tracked"
  assert_summary "3 files · +4 -0"
  # Same tree, now with a global ignore rule covering that directory.
  printf 'globaljunk/\n' > "$BATS_TEST_TMPDIR/empty-excludes"
  assert_summary "1 file · +1 -0"
}

@test "honors .git/info/exclude" {
  init_repo
  GIT checkout -q -b feature
  printf 'scratch/\n' > "$REPO/.git/info/exclude"
  mkdir -p "$REPO/scratch"
  printf 'a\nb\n' > "$REPO/scratch/notes"
  printf 'base\nreal work\n' > "$REPO/tracked"
  assert_summary "1 file · +1 -0"
}

@test "still counts a file that is ignored by a rule it does not match" {
  init_repo
  printf 'node_modules/\n' > "$REPO/.gitignore"
  GIT add .gitignore
  GIT commit -q -m ignore
  GIT checkout -q -b feature
  printf 'a\nb\n' > "$REPO/node_modules_notes.md"
  assert_summary "1 file · +2 -0"
}


################################
# Hostile working trees        #
################################

@test "a dangling symlink does not zero the other counts" {
  init_repo
  printf 'a\nb\nc\nd\ne\n' > "$REPO/f1"
  printf 'a\nb\nc\nd\ne\n' > "$REPO/f2"
  assert_summary "2 files · +10 -0"
  ln -s /nonexistent-target-xyz "$REPO/dangling"
  # The link itself counts as one file of one line (git stores the target
  # string); crucially the other ten lines survive.
  assert_summary "3 files · +11 -0"
}

@test "a symlink to an endless device does not hang or inflate the count" {
  init_repo
  printf 'a\nb\n' > "$REPO/real"
  ln -s /dev/zero "$REPO/endless"
  # git reads the link, never its target, so this terminates.
  assert_summary "2 files · +3 -0"
}

@test "an unreadable file is skipped without blanking the whole summary" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "root can read mode-000 files, so the failure path never triggers"
  fi
  init_repo
  printf 'a\nb\nc\n' > "$REPO/readable"
  printf 'secret\n' > "$REPO/unreadable"
  chmod 000 "$REPO/unreadable"
  # The unreadable file drops out; everything else still counts.
  assert_summary "1 file · +3 -0"
  chmod 644 "$REPO/unreadable"
}

@test "counts untracked files whose names contain spaces" {
  init_repo
  printf 'one\ntwo\n' > "$REPO/two words.txt"
  printf 'three\n' > "$REPO/another one.txt"
  assert_summary "2 files · +3 -0"
}

@test "counts an untracked file whose name looks like an awk assignment" {
  init_repo
  printf 'x\ny\nz\n' > "$REPO/foo=bar"
  assert_summary "1 file · +3 -0"
}

@test "counts an untracked file named exactly -" {
  init_repo
  printf 'dash\ncontent\n' > "$REPO/-"
  assert_summary "1 file · +2 -0"
}

@test "counts a file whose name contains a newline" {
  init_repo
  printf 'a\nb\n' > "$REPO/we
ird"
  assert_summary "1 file · +2 -0"
}

@test "counts a binary file as changed without counting its bytes as lines" {
  init_repo
  printf '\000\001\002binary\000payload\n' > "$REPO/blob.bin"
  # Untracked binary: git's own binary detection applies, so no line count.
  assert_summary "1 file · +0 -0"
  GIT add blob.bin
  GIT commit -q -m blob
  printf '\000\003\004\005more\000bytes\n' > "$REPO/blob.bin"
  # Tracked binary, modified: same treatment.
  assert_summary "1 file · +0 -0"
}

@test "does not count lines for a file past the big-file threshold" {
  init_repo
  # 9MB of newline-terminated text, over the 8m cap: counted as a changed file
  # with no line count rather than re-read in full on every tick.
  awk 'BEGIN { for (i = 0; i < 600000; i++) print "0123456789abcde" }' \
    > "$REPO/huge.txt"
  assert_summary "1 file · +0 -0"
}


################################
# Does not disturb the repo    #
################################

@test "leaves the real index and the staged state untouched" {
  init_repo
  GIT checkout -q -b feature
  printf 'staged\n' > "$REPO/staged"
  GIT add staged
  printf 'untracked\n' > "$REPO/untracked"
  before_index=$(md5sum < "$REPO/.git/index" 2>/dev/null || md5 < "$REPO/.git/index")
  before_status=$(GIT status --porcelain)
  assert_summary "2 files · +2 -0"
  after_index=$(md5sum < "$REPO/.git/index" 2>/dev/null || md5 < "$REPO/.git/index")
  after_status=$(GIT status --porcelain)
  [ "$before_index" = "$after_index" ]
  [ "$before_status" = "$after_status" ]
  # The untracked file must still be untracked, not intent-to-add.
  printf '%s\n' "$after_status" | grep -q '^?? untracked$'
}

@test "leaves no temp index files behind" {
  init_repo
  printf 'a\n' > "$REPO/new"
  # A private TMPDIR rather than counting files in the shared one: the live
  # ticker on a real machine writes there too, which would make this flaky.
  mkdir -p "$BATS_TEST_TMPDIR/tmp"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(plain "$output")" = "1 file · +1 -0" ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp")" ]
}

@test "works from inside a linked worktree" {
  init_repo
  printf 'a\nb\n' > "$REPO/on-main"
  GIT add on-main
  GIT commit -q -m more
  GIT worktree add -q "$BATS_TEST_TMPDIR/wt" -b wtbranch
  printf 'w\nx\ny\n' > "$BATS_TEST_TMPDIR/wt/wt-only"
  assert_summary "1 file · +3 -0" "$BATS_TEST_TMPDIR/wt"
}

@test "reports the whole repo when diff.relative is set and run from a subdir" {
  init_repo
  GIT config diff.relative true
  mkdir -p "$REPO/sub"
  printf 'inner\n' > "$REPO/sub/inner"
  GIT add sub
  GIT commit -q -m sub
  GIT checkout -q -b feature
  printf 'base\nroot-change\n' > "$REPO/tracked"
  # diff.relative would otherwise scope the diff to sub/ and report nothing.
  assert_summary "1 file · +1 -0" "$REPO/sub"
}


################################
# Output shape                 #
################################

@test "emits green and red style tags around the counts" {
  init_repo
  printf 'base\nadded\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = '1 file · #[fg=colour2]+1#[default] #[fg=colour1]-0#[default]' ]
}

@test "output carries no format sequence that #{E:} could evaluate" {
  init_repo
  printf 'base\nadded\n' > "$REPO/tracked"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  # "#[" style tags are fine and expected; "#{" and "#(" would be re-evaluated
  # by the #{E:...} expansion in tmux.conf.
  [ "${output##*'#{'}" = "$output" ]
  [ "${output##*'#('}" = "$output" ]
}
