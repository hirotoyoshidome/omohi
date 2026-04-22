#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <omohi-binary>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.github/scripts/omohi_test_lib.sh
source "$SCRIPT_DIR/omohi_test_lib.sh"

init_omohi_test_env "$1" "omohi-e2e-matrix"

CASE_COUNTER=0

run_case() {
  local case_name="$1"
  shift

  CASE_COUNTER=$((CASE_COUNTER + 1))
  printf '[case %03d] %s\n' "$CASE_COUNTER" "$case_name"
  reset_omohi_test_env
  "$@"
}

extract_commit_id() {
  local text="$1"

  printf '%s\n' "$text" | sed -n 's/^Committed \([0-9a-f]\{64\}\)\.$/\1/p'
}

extract_tracked_id_for_path() {
  local path="$1"

  run_omohi_capture tracklist
  assert_eq "0" "$RUN_CODE" "tracklist should succeed while extracting tracked id"
  printf '%s\n' "$RUN_STDOUT" | awk -v target="$path" '$2 == target { print $1; exit }'
}

commit_expect_success() {
  local message="$1"
  shift

  run_omohi_capture commit -m "$message" "$@"
  assert_eq "0" "$RUN_CODE" "commit should succeed"
  LAST_COMMIT_ID="$(extract_commit_id "$RUN_STDOUT")"
  if [ -z "$LAST_COMMIT_ID" ]; then
    echo "failed to extract commit id from commit output" >&2
    echo "$RUN_STDOUT" >&2
    exit 1
  fi
}

current_local_date() {
  date '+%Y-%m-%d'
}

make_long_tag() {
  printf '%256s' '' | tr ' ' 'a'
}

assert_path_listed() {
  local text="$1"
  local path="$2"
  assert_contains "$text" "$path" "output should include path $path"
}

assert_line_order() {
  local text="$1"
  local first="$2"
  local second="$3"
  local first_line second_line

  first_line="$(printf '%s\n' "$text" | grep -nF "$first" | head -n 1 | cut -d: -f1)"
  second_line="$(printf '%s\n' "$text" | grep -nF "$second" | head -n 1 | cut -d: -f1)"

  if [ -z "$first_line" ] || [ -z "$second_line" ] || [ "$first_line" -ge "$second_line" ]; then
    echo "assert_line_order failed" >&2
    echo "  first:  $first" >&2
    echo "  second: $second" >&2
    echo "  text:   $text" >&2
    exit 1
  fi
}

setup_two_tracked_files() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "track should succeed for two files"
}

setup_commit_with_two_files_and_tags() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed for two tracked files"
  commit_expect_success "first" -t alpha -t beta
}

setup_commit_without_tags() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  run_omohi_capture track "$FILE_A"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"
}

setup_two_commits_for_find() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should succeed for first commit"
  commit_expect_success "first" -t release
  FIRST_COMMIT_ID="$LAST_COMMIT_ID"
  printf 'beta-updated\n' > "$FILE_B"
  run_omohi_capture add "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed for second commit"
  commit_expect_success "second" -t release -t prod
  SECOND_COMMIT_ID="$LAST_COMMIT_ID"
  FIND_DATE="$(current_local_date)"
}

case_001_track_single_file() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"

  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed for one file"
  assert_contains "$RUN_STDOUT" "Tracked: $file" "track should report tracked file"
}

case_002_track_multiple_files() {
  setup_two_tracked_files
  assert_contains "$RUN_STDOUT" "Tracked 2 file(s)." "track should report multiple files"
  assert_path_listed "$RUN_STDOUT" "$FILE_A"
  assert_path_listed "$RUN_STDOUT" "$FILE_B"
}

case_003_track_directory_recursive() {
  local dir
  dir="$WORK_DIR/tree"
  mkdir -p "$dir/sub"
  printf 'a\n' > "$dir/a.txt"
  printf 'b\n' > "$dir/sub/b.txt"

  run_omohi_capture track "$dir"
  assert_eq "0" "$RUN_CODE" "track should succeed for directory"
  assert_contains "$RUN_STDOUT" "Tracked 2 file(s) under $dir" "track should report recursive count"
  assert_path_listed "$RUN_STDOUT" "$dir/a.txt"
  assert_path_listed "$RUN_STDOUT" "$dir/sub/b.txt"
}

case_004_track_already_tracked() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "first track should succeed"

  run_omohi_capture track "$file"
  assert_eq "4" "$RUN_CODE" "second track should report already tracked file"
  assert_contains "$RUN_STDERR" "The file is already tracked." "track should report already tracked file"
}

case_005_track_directory_skips_non_regular() {
  local dir
  dir="$WORK_DIR/tree"
  mkdir -p "$dir/subdir"
  printf 'a\n' > "$dir/a.txt"
  printf 'b\n' > "$dir/subdir/b.txt"
  ln -s "$dir/a.txt" "$dir/link.txt"

  run_omohi_capture track "$dir"
  assert_eq "0" "$RUN_CODE" "track should succeed for mixed directory"
  assert_contains "$RUN_STDOUT" "Tracked 2 file(s) under $dir" "track should report only regular files"
  assert_not_contains "$RUN_STDOUT" "$dir/link.txt" "track should skip symlink entries"
}

case_006_track_missing_path() {
  run_omohi_capture track "$WORK_DIR/missing.txt"
  assert_eq "0" "$RUN_CODE" "track currently accepts missing absolute paths"
  assert_contains "$RUN_STDOUT" "Tracked: $WORK_DIR/missing.txt" "track should report registered path"
}

case_007_untrack_by_id() {
  local file tracked_id
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  tracked_id="$(extract_tracked_id_for_path "$file")"

  run_omohi_capture untrack "$tracked_id"
  assert_eq "0" "$RUN_CODE" "untrack should succeed"
  assert_contains "$RUN_STDOUT" "Untracked: $file" "untrack should report file"
}

case_008_untrack_missing_batch() {
  setup_two_tracked_files
  rm -f "$FILE_A" "$FILE_B"

  run_omohi_capture untrack --missing
  assert_eq "0" "$RUN_CODE" "untrack --missing should succeed"
  assert_contains "$RUN_STDOUT" "Untracked 2 missing tracked file(s)." "untrack --missing should report count"
  assert_path_listed "$RUN_STDOUT" "$FILE_A"
  assert_path_listed "$RUN_STDOUT" "$FILE_B"
}

case_009_untrack_missing_none() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture untrack --missing
  assert_eq "0" "$RUN_CODE" "untrack --missing should succeed with no missing files"
  assert_contains "$RUN_STDOUT" "No missing tracked files to untrack." "untrack --missing should report nothing to do"
}

case_010_untrack_missing_with_positional() {
  local file tracked_id
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  tracked_id="$(extract_tracked_id_for_path "$file")"

  run_omohi_capture untrack --missing "$tracked_id"
  assert_eq "2" "$RUN_CODE" "untrack --missing should reject positional args"
  assert_contains "$RUN_STDERR" "Unexpected argument." "untrack --missing should reject positional args"
}

case_011_untrack_missing_with_value() {
  run_omohi_capture untrack --missing=yes
  assert_eq "2" "$RUN_CODE" "untrack --missing=value should be rejected"
  assert_contains "$RUN_STDERR" "Unknown option." "untrack --missing=value should report unknown option"
}

case_012_untrack_unknown_id() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture untrack 00000000000000000000000000000000
  assert_eq "4" "$RUN_CODE" "untrack should fail for unknown tracked id"
  assert_contains "$RUN_STDERR" "Target not found." "untrack should report target not found"
}

case_013_add_single_tracked_file() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  assert_contains "$RUN_STDOUT" "Staged: $file" "add should report staged file"
}

case_014_add_multiple_tracked_files() {
  setup_two_tracked_files

  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed for multiple files"
  assert_contains "$RUN_STDOUT" "Staged 2 file(s)." "add should report multiple staged files"
  assert_path_listed "$RUN_STDOUT" "$FILE_A"
  assert_path_listed "$RUN_STDOUT" "$FILE_B"
}

case_015_add_directory_recursive() {
  local dir
  dir="$WORK_DIR/tree"
  mkdir -p "$dir/sub"
  printf 'a\n' > "$dir/a.txt"
  printf 'b\n' > "$dir/sub/b.txt"
  run_omohi_capture track "$dir"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture add "$dir"
  assert_eq "0" "$RUN_CODE" "add should succeed for tracked directory"
  assert_contains "$RUN_STDOUT" "Staged 2 file(s) under $dir" "add should report recursive staging"
}

case_016_add_all_short_option() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "initial add should succeed"
  commit_expect_success "baseline"
  printf 'alpha-updated\n' > "$FILE_A"
  printf 'beta-updated\n' > "$FILE_B"

  run_omohi_capture add -a
  assert_eq "0" "$RUN_CODE" "add -a should succeed"
  assert_contains "$RUN_STDOUT" "Staged 2 file(s)." "add -a should stage changed files"
}

case_017_add_all_long_option() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "initial add should succeed"
  commit_expect_success "baseline"
  printf 'alpha-updated\n' > "$FILE_A"

  run_omohi_capture add --all
  assert_eq "0" "$RUN_CODE" "add --all should succeed"
  assert_contains "$RUN_STDOUT" "Staged 1 file(s)." "add --all should stage changed files"
  assert_contains "$RUN_STDOUT" "$FILE_A" "add --all should include changed file"
}

case_018_add_already_staged() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "first add should succeed"

  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "second add should succeed"
  assert_contains "$RUN_STDOUT" "Staged: $file" "second add currently restages the same file"
}

case_019_add_unchanged_tracked_file() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "initial add should succeed"
  commit_expect_success "baseline"

  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add on unchanged file should succeed"
  assert_contains "$RUN_STDOUT" "No changes to stage: $file" "add should report no changes"
}

case_020_add_missing_tracked_file() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  rm -f "$file"

  run_omohi_capture add "$file"
  assert_eq "4" "$RUN_CODE" "add should fail for missing tracked file"
  assert_contains "$RUN_STDERR" "Tracked file is missing: $file" "add should report missing tracked file"
  assert_contains "$RUN_STDERR" "omohi untrack --missing" "add should suggest cleanup command"
}

case_021_add_untracked_path() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"

  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$WORK_DIR/untracked.txt"
  assert_eq "4" "$RUN_CODE" "add should fail for untracked path"
  assert_contains "$RUN_STDERR" "Tracked file not found: $WORK_DIR/untracked.txt" "add should report untracked path"
}

case_022_add_all_with_path() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture add -a "$file"
  assert_eq "2" "$RUN_CODE" "add -a with explicit path should fail"
  assert_contains "$RUN_STDERR" "Unexpected argument." "add -a with path should report usage error"
}

case_023_add_all_with_value() {
  run_omohi_capture add --all=value
  assert_eq "2" "$RUN_CODE" "add --all=value should fail"
  assert_contains "$RUN_STDERR" "Unknown option." "add --all=value should report unknown option"
}

case_024_add_double_dash_positional() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture add -- --all
  assert_eq "4" "$RUN_CODE" "add should treat --all as positional path after --"
  assert_contains "$RUN_STDERR" "Tracked file not found:" "add should treat --all as path"
  assert_contains "$RUN_STDERR" "/--all" "add should resolve the positional path"
}

case_025_rm_single_staged_file() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture rm "$file"
  assert_eq "0" "$RUN_CODE" "rm should succeed for staged file"
  assert_contains "$RUN_STDOUT" "Unstaged: $file" "rm should report unstaged file"
}

case_026_rm_multiple_staged_files() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture rm "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "rm should succeed for multiple files"
  assert_contains "$RUN_STDOUT" "Unstaged 2 file(s)." "rm should report multiple unstaged files"
  assert_path_listed "$RUN_STDOUT" "$FILE_A"
  assert_path_listed "$RUN_STDOUT" "$FILE_B"
}

case_027_rm_directory_recursive() {
  local dir
  dir="$WORK_DIR/tree"
  mkdir -p "$dir/sub"
  printf 'a\n' > "$dir/a.txt"
  printf 'b\n' > "$dir/sub/b.txt"
  run_omohi_capture track "$dir"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$dir"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture rm "$dir"
  assert_eq "0" "$RUN_CODE" "rm should succeed for directory"
  assert_contains "$RUN_STDOUT" "Unstaged 2 file(s) under $dir" "rm should report recursive unstage"
}

case_028_rm_tracked_but_not_staged() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture rm "$file"
  assert_eq "4" "$RUN_CODE" "rm should fail for non-staged tracked file"
  assert_contains "$RUN_STDERR" "Staged file not found: $file" "rm should report staged file not found"
}

case_029_rm_untracked_path() {
  local file tracked
  file="$(make_note_file "note.txt" $'first version\n')"
  tracked="$(make_note_file "tracked.txt" $'tracked\n')"
  run_omohi_capture track "$tracked"
  assert_eq "0" "$RUN_CODE" "track should initialize store"

  run_omohi_capture rm "$file"
  assert_eq "4" "$RUN_CODE" "rm should fail for untracked path"
  assert_contains "$RUN_STDERR" "Tracked file not found: $file" "rm should report tracked file not found"
}

case_030_rm_mixed_with_non_staged() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should succeed for first file"

  run_omohi_capture rm "$FILE_A" "$FILE_B"
  assert_eq "4" "$RUN_CODE" "rm currently fails when any requested file is not staged"
  assert_contains "$RUN_STDERR" "Staged file not found: $FILE_B" "rm should report the non-staged file"
}

case_030_rm_all_short_option() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture rm -a
  assert_eq "0" "$RUN_CODE" "rm -a should succeed"
  assert_contains "$RUN_STDOUT" "Unstaged 2 file(s)." "rm -a should report all unstaged files"
  assert_path_listed "$RUN_STDOUT" "$FILE_A"
  assert_path_listed "$RUN_STDOUT" "$FILE_B"
}

case_030_rm_all_long_option_with_deleted_source() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  rm -f "$file"

  run_omohi_capture rm --all
  assert_eq "0" "$RUN_CODE" "rm --all should succeed for deleted staged source"
  assert_contains "$RUN_STDOUT" "Unstaged 1 file(s)." "rm --all should report one unstaged file"
  assert_path_listed "$RUN_STDOUT" "$file"
}

case_030_rm_all_mixed_with_path() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture rm -a "$file"
  assert_eq "2" "$RUN_CODE" "rm -a with explicit path should fail"
  assert_contains "$RUN_STDERR" "Unexpected argument." "rm -a with path should report usage error"
}

case_030_rm_all_with_value() {
  run_omohi_capture rm --all=value
  assert_eq "2" "$RUN_CODE" "rm --all=value should fail"
  assert_contains "$RUN_STDERR" "Unknown option." "rm --all=value should report unknown option"
}

case_030_rm_double_dash_positional() {
  local tracked
  tracked="$(make_note_file "tracked.txt" $'tracked\n')"
  run_omohi_capture track "$tracked"
  assert_eq "0" "$RUN_CODE" "track should initialize store"

  run_omohi_capture rm -- --all
  assert_eq "4" "$RUN_CODE" "rm should treat --all as positional path after --"
  assert_contains "$RUN_STDERR" "Tracked file not found:" "rm should treat --all as path"
  assert_contains "$RUN_STDERR" "/--all" "rm should resolve the positional path"
}

case_031_commit_short_message_option() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture commit -m "first"
  assert_eq "0" "$RUN_CODE" "commit -m should succeed"
  assert_matches "$RUN_STDOUT" '^Committed [0-9a-f]{64}\.$' "commit should print commit id"
}

case_032_commit_long_message_option() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture commit --message "first"
  assert_eq "0" "$RUN_CODE" "commit --message should succeed"
  assert_matches "$RUN_STDOUT" '^Committed [0-9a-f]{64}\.$' "commit should print commit id"
}

case_033_commit_with_multiple_tags() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  commit_expect_success "first" -t release --tag prod
  run_omohi_capture tag ls "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "tag ls should succeed"
  assert_contains "$RUN_STDOUT" "release" "commit should attach release tag"
  assert_contains "$RUN_STDOUT" "prod" "commit should attach prod tag"
}

case_034_commit_dry_run() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture commit -m "first" --dry-run
  assert_eq "0" "$RUN_CODE" "commit --dry-run should succeed"
  assert_contains "$RUN_STDOUT" "Dry run: commit prepared but not written." "dry-run should report preview"
  assert_contains "$RUN_STDOUT" "dry-run staged count: 2" "dry-run should report staged count"
  assert_path_listed "$RUN_STDOUT" "$FILE_A"
  assert_path_listed "$RUN_STDOUT" "$FILE_B"
  assert_file_missing "$HOME_DIR/.omohi/HEAD" "dry-run should not write HEAD"
}

case_035_commit_dry_run_marks_missing() {
  setup_two_tracked_files
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  rm -f "$FILE_B"

  run_omohi_capture commit -m "first" --dry-run
  assert_eq "0" "$RUN_CODE" "commit --dry-run should succeed"
  assert_contains "$RUN_STDOUT" "- $FILE_B (missing)" "dry-run should mark missing current file"
}

case_036_commit_requires_message() {
  run_omohi_capture commit
  assert_eq "2" "$RUN_CODE" "commit should require message"
  assert_contains "$RUN_STDERR" "Missing required argument." "commit should report missing message"

  run_omohi_capture commit --dry-run
  assert_eq "2" "$RUN_CODE" "commit --dry-run should also require message"
  assert_contains "$RUN_STDERR" "Missing required argument." "commit --dry-run should report missing message"
}

case_037_commit_requires_staged_files() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture commit -m "first"
  assert_eq "10" "$RUN_CODE" "commit without staged files currently reports a system error"
  assert_contains "$RUN_STDERR" "unexpected system error" "commit without staged files currently uses generic runtime guidance"
}

case_038_commit_uppercase_option_keys() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture commit -M "first" --TAG=release --DRY-RUN
  assert_eq "0" "$RUN_CODE" "commit should accept uppercase option keys"
  assert_contains "$RUN_STDOUT" "Dry run: commit prepared but not written." "uppercase options should behave like normal dry-run"
}

case_039_commit_double_dash_extra_args() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture commit -m "first" -- --tag release
  assert_eq "2" "$RUN_CODE" "commit should reject positional args after --"
  assert_contains "$RUN_STDERR" "Unexpected argument." "commit should report unexpected argument"
}

case_040_status_clean() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "no staged, changed, or missing tracked files" "status should report clean state"
}

case_041_status_staged_only() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "staged: $file" "status should report staged file"
}

case_042_status_changed_only() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"
  printf 'second version\n' > "$file"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "changed: $file" "status should report changed file"
}

case_043_status_missing_only() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  rm -f "$file"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "missing: $file" "status should report missing file"
  assert_contains "$RUN_STDOUT" "Missing tracked files remain." "status should include warning"
}

case_044_status_staged_and_changed() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"
  printf 'alpha-updated\n' > "$FILE_A"
  printf 'beta-updated\n' > "$FILE_B"
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should restage first file"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "staged: $FILE_A" "status should list staged file"
  assert_contains "$RUN_STDOUT" "changed: $FILE_B" "status should list changed file"
  assert_line_order "$RUN_STDOUT" "staged: $FILE_A" "changed: $FILE_B"
}

case_045_status_staged_and_missing() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  rm -f "$FILE_B"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "staged: $FILE_A" "status should list staged file"
  assert_contains "$RUN_STDOUT" "missing: $FILE_B" "status should list missing file"
  assert_line_order "$RUN_STDOUT" "staged: $FILE_A" "missing: $FILE_B"
  assert_contains "$RUN_STDOUT" "Missing tracked files remain." "status should include warning"
}

case_046_status_changed_and_missing() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A" "$FILE_B"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"
  printf 'alpha-updated\n' > "$FILE_A"
  rm -f "$FILE_B"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "changed: $FILE_A" "status should list changed file"
  assert_contains "$RUN_STDOUT" "missing: $FILE_B" "status should list missing file"
  assert_line_order "$RUN_STDOUT" "changed: $FILE_A" "missing: $FILE_B"
  assert_contains "$RUN_STDOUT" "Missing tracked files remain." "status should include warning"
}

case_047_status_staged_changed_missing() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  FILE_C="$(make_note_file "c.txt" $'gamma\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B" "$FILE_C"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A" "$FILE_B" "$FILE_C"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"
  printf 'alpha-updated\n' > "$FILE_A"
  printf 'beta-updated\n' > "$FILE_B"
  rm -f "$FILE_C"
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should restage first file"

  run_omohi_capture status
  assert_eq "0" "$RUN_CODE" "status should succeed"
  assert_contains "$RUN_STDOUT" "staged: $FILE_A" "status should list staged file"
  assert_contains "$RUN_STDOUT" "changed: $FILE_B" "status should list changed file"
  assert_contains "$RUN_STDOUT" "missing: $FILE_C" "status should list missing file"
  assert_line_order "$RUN_STDOUT" "staged: $FILE_A" "changed: $FILE_B"
  assert_line_order "$RUN_STDOUT" "changed: $FILE_B" "missing: $FILE_C"
  assert_contains "$RUN_STDOUT" "Missing tracked files remain." "status should include warning"
}

case_048_status_tty_colors() {
  FILE_A="$(make_note_file "a.txt" $'alpha\n')"
  FILE_B="$(make_note_file "b.txt" $'beta\n')"
  FILE_C="$(make_note_file "c.txt" $'gamma\n')"
  run_omohi_capture track "$FILE_A" "$FILE_B" "$FILE_C"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$FILE_A" "$FILE_B" "$FILE_C"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"
  printf 'alpha-updated\n' > "$FILE_A"
  printf 'beta-updated\n' > "$FILE_B"
  rm -f "$FILE_C"
  run_omohi_capture add "$FILE_A"
  assert_eq "0" "$RUN_CODE" "add should restage first file"

  run_omohi_capture_tty status
  assert_eq "0" "$RUN_CODE" "status should succeed under tty"
  assert_contains "$RUN_STDOUT" $'\033[32mstaged:\033[0m' "tty status should color staged label"
  assert_matches "$RUN_STDOUT" $'\033\\[[0-9;]+mchanged:\033\\[0m' "tty status should color changed label"
  assert_matches "$RUN_STDOUT" $'\033\\[[0-9;]+mmissing:\033\\[0m' "tty status should color missing label"
}

case_049_tracklist_text_default() {
  setup_two_tracked_files
  run_omohi_capture tracklist
  assert_eq "0" "$RUN_CODE" "tracklist should succeed"
  assert_matches "$RUN_STDOUT" "^[0-9a-f]{32} $FILE_A" "tracklist should include first file"
  assert_matches "$RUN_STDOUT" "[0-9a-f]{32} $FILE_B$" "tracklist should include second file"
}

case_050_tracklist_empty() {
  run_omohi_capture tracklist
  assert_eq "4" "$RUN_CODE" "tracklist without store should fail"
  assert_contains "$RUN_STDERR" "Store is not initialized." "tracklist should report missing store before initialization"

  reset_omohi_test_env
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  local tracked_id
  tracked_id="$(extract_tracked_id_for_path "$file")"
  run_omohi_capture untrack "$tracked_id"
  assert_eq "0" "$RUN_CODE" "untrack should succeed"

  run_omohi_capture tracklist
  assert_eq "0" "$RUN_CODE" "tracklist should succeed with initialized empty store"
  assert_contains "$RUN_STDOUT" "no tracked files" "tracklist should report empty state"
}

case_051_tracklist_json_output() {
  setup_two_tracked_files
  run_omohi_capture tracklist --output json
  assert_eq "0" "$RUN_CODE" "tracklist --output json should succeed"
  assert_contains "$RUN_STDOUT" '"id":"' "tracklist json should include id field"
  assert_contains "$RUN_STDOUT" "\"path\":\"$FILE_A\"" "tracklist json should include first path"
  assert_contains "$RUN_STDOUT" "\"path\":\"$FILE_B\"" "tracklist json should include second path"
}

case_052_tracklist_field_id_only() {
  setup_two_tracked_files
  run_omohi_capture tracklist --field id
  assert_eq "0" "$RUN_CODE" "tracklist --field id should succeed"
  assert_matches "$RUN_STDOUT" "^[0-9a-f]{32}(\n[0-9a-f]{32})?$" "tracklist --field id should show only ids"
}

case_053_tracklist_field_id_path() {
  setup_two_tracked_files
  run_omohi_capture tracklist --field id --field path
  assert_eq "0" "$RUN_CODE" "tracklist field selection should succeed"
  assert_matches "$RUN_STDOUT" "^[0-9a-f]{32} $FILE_A" "tracklist should keep id path ordering"
  assert_matches "$RUN_STDOUT" "[0-9a-f]{32} $FILE_B$" "tracklist should include second file"
}

case_054_tracklist_json_with_fields() {
  setup_two_tracked_files
  run_omohi_capture tracklist --output json --field id --field path
  assert_eq "0" "$RUN_CODE" "tracklist json with fields should succeed"
  assert_contains "$RUN_STDOUT" '"id":"' "tracklist json should include id"
  assert_contains "$RUN_STDOUT" '"path":"' "tracklist json should include path"
}

case_055_tracklist_unknown_field() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"

  run_omohi_capture tracklist --field unknown
  assert_eq "2" "$RUN_CODE" "tracklist unknown field should be rejected"
  assert_contains "$RUN_STDERR" "Invalid CLI input." "tracklist should report invalid field"
}

case_056_version_command() {
  run_omohi_capture version
  assert_eq "0" "$RUN_CODE" "version should succeed"
  assert_matches "$RUN_STDOUT" '^omohi version .+ \([^)]+\)$' "version should include version and target"
}

case_057_version_short_alias() {
  run_omohi_capture -v
  assert_eq "0" "$RUN_CODE" "short version alias should succeed"
  assert_contains "$RUN_STDOUT" "omohi version " "short version alias should match version output"
}

case_058_version_long_alias() {
  run_omohi_capture --version
  assert_eq "0" "$RUN_CODE" "long version alias should succeed"
  assert_contains "$RUN_STDOUT" "omohi version " "long version alias should match version output"
}

case_059_version_rejects_extra_args() {
  run_omohi_capture version extra
  assert_eq "2" "$RUN_CODE" "version should reject extra args"
  assert_contains "$RUN_STDERR" "Unexpected argument." "version should report usage error"
}

case_060_find_all_commits_text() {
  setup_two_commits_for_find
  run_omohi_capture find
  assert_eq "0" "$RUN_CODE" "find should succeed"
  assert_contains "$RUN_STDOUT" "Found 2 commit(s)." "find should report both commits"
  assert_contains "$RUN_STDOUT" "$FIRST_COMMIT_ID" "find should include first commit"
  assert_contains "$RUN_STDOUT" "$SECOND_COMMIT_ID" "find should include second commit"
}

case_061_find_by_tag() {
  setup_two_commits_for_find
  run_omohi_capture find --tag release
  assert_eq "0" "$RUN_CODE" "find --tag should succeed"
  assert_contains "$RUN_STDOUT" "Found 2 commit(s) for tag release." "find should report tag filter"
}

case_062_find_by_since() {
  setup_two_commits_for_find
  run_omohi_capture find --since "$FIND_DATE"
  assert_eq "0" "$RUN_CODE" "find --since should succeed"
  assert_contains "$RUN_STDOUT" "Found 2 commit(s) since $FIND_DATE." "find should report since filter"
}

case_063_find_by_tag_and_range() {
  setup_two_commits_for_find
  run_omohi_capture find --tag release --since "$FIND_DATE" --until "${FIND_DATE}T23:59:59"
  assert_eq "0" "$RUN_CODE" "find with tag and range should succeed"
  assert_contains "$RUN_STDOUT" "Found 2 commit(s) for tag release from $FIND_DATE until ${FIND_DATE}T23:59:59." "find should report both filters"
}

case_064_find_empty() {
  run_omohi_capture find
  assert_eq "4" "$RUN_CODE" "find without initialized store should fail"
  assert_contains "$RUN_STDERR" "Store is not initialized." "find should report missing store before initialization"

  reset_omohi_test_env
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture find
  assert_eq "0" "$RUN_CODE" "find should succeed on initialized empty store"
  assert_contains "$RUN_STDOUT" "no commits" "find should report empty commit list"
}

case_065_find_json_output() {
  setup_two_commits_for_find
  run_omohi_capture find --output json
  assert_eq "0" "$RUN_CODE" "find json should succeed"
  assert_contains "$RUN_STDOUT" "\"commit_id\":\"$FIRST_COMMIT_ID\"" "find json should include first commit id"
  assert_contains "$RUN_STDOUT" '"message":"' "find json should include message"
  assert_contains "$RUN_STDOUT" '"created_at":"' "find json should include created_at"
}

case_066_find_text_fields() {
  setup_two_commits_for_find
  run_omohi_capture find --field commit_id --field created_at
  assert_eq "0" "$RUN_CODE" "find field output should succeed"
  assert_matches "$RUN_STDOUT" "$FIRST_COMMIT_ID [0-9T:+.-]+" "find field output should include commit_id and created_at"
}

case_067_find_json_with_fields() {
  setup_two_commits_for_find
  run_omohi_capture find --output json --field commit_id
  assert_eq "0" "$RUN_CODE" "find json with fields should succeed"
  assert_contains "$RUN_STDOUT" "\"commit_id\":\"$FIRST_COMMIT_ID\"" "find json should include selected commit id"
  assert_not_contains "$RUN_STDOUT" '"message":"' "find json should omit non-selected fields"
}

case_068_find_unknown_field() {
  setup_two_commits_for_find
  run_omohi_capture find --field unknown
  assert_eq "2" "$RUN_CODE" "find unknown field should be rejected"
  assert_contains "$RUN_STDERR" "Invalid CLI input." "find should report invalid field"
}

case_069_find_invalid_date() {
  setup_two_commits_for_find
  run_omohi_capture find --since 2026/03/12
  assert_eq "2" "$RUN_CODE" "find invalid date should be rejected"
  assert_contains "$RUN_STDERR" "Invalid date/time input. Use YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS" "find should report invalid date"
}

case_070_find_uppercase_option_keys() {
  setup_two_commits_for_find
  run_omohi_capture find --TAG release --SINCE="$FIND_DATE" --UNTIL "${FIND_DATE}T23:59:59"
  assert_eq "0" "$RUN_CODE" "find should accept uppercase option keys"
  assert_contains "$RUN_STDOUT" "Found 2 commit(s) for tag release from $FIND_DATE until ${FIND_DATE}T23:59:59." "uppercase options should behave normally"
}

case_071_find_double_dash_extra_args() {
  setup_two_commits_for_find
  run_omohi_capture find -- --tag release
  assert_eq "2" "$RUN_CODE" "find should reject extra args after --"
  assert_contains "$RUN_STDERR" "Unexpected argument." "find should report unexpected argument"
}

case_072_show_text_default() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture show "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "show should succeed"
  assert_contains "$RUN_STDOUT" "Found commit $LAST_COMMIT_ID" "show should report commit header"
  assert_contains "$RUN_STDOUT" "commit changes:" "show should report changed paths"
  assert_contains "$RUN_STDOUT" "tags:" "show should report tags"
  assert_contains "$RUN_STDOUT" "- alpha" "show should include first tag"
}

case_073_show_without_tags() {
  setup_commit_without_tags
  run_omohi_capture show "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "show should succeed"
  assert_contains "$RUN_STDOUT" "tags:" "show should include tags section"
  assert_contains "$RUN_STDOUT" "- (none)" "show should report no tags"
}

case_074_show_json_output() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture show --output json "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "show json should succeed"
  assert_contains "$RUN_STDOUT" "\"commit_id\":\"$LAST_COMMIT_ID\"" "show json should include commit id"
  assert_contains "$RUN_STDOUT" '"paths":[' "show json should include paths"
  assert_contains "$RUN_STDOUT" '"tags":[' "show json should include tags"
}

case_075_show_text_fields() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture show --field commit_id --field tags "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "show field output should succeed"
  assert_contains "$RUN_STDOUT" "$LAST_COMMIT_ID " "show field output should include commit id"
  assert_contains "$RUN_STDOUT" "alpha" "show field output should include alpha tag"
  assert_contains "$RUN_STDOUT" "beta" "show field output should include beta tag"
}

case_076_show_options_before_positional() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture show --output text --field commit_id "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "show should accept options before positional"
  assert_eq "$LAST_COMMIT_ID" "$RUN_STDOUT" "show field output should be commit id only"
}

case_077_show_unknown_field() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture show --field unknown "$LAST_COMMIT_ID"
  assert_eq "2" "$RUN_CODE" "show unknown field should be rejected"
  assert_contains "$RUN_STDERR" "Invalid CLI input." "show should report invalid field"
}

case_078_show_unknown_commit() {
  setup_commit_without_tags
  run_omohi_capture show 0000000000000000000000000000000000000000000000000000000000000000
  assert_eq "4" "$RUN_CODE" "show should fail for unknown commit"
  assert_contains "$RUN_STDERR" "Commit not found:" "show should report unknown commit"
}

case_079_journal_non_empty() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  run_omohi_capture add "$file"
  assert_eq "0" "$RUN_CODE" "add should succeed"
  commit_expect_success "first"

  run_omohi_capture journal
  assert_eq "0" "$RUN_CODE" "journal should succeed"
  assert_contains "$RUN_STDOUT" " commit " "journal should include commit event"
  assert_contains "$RUN_STDOUT" " add " "journal should include add event"
  assert_contains "$RUN_STDOUT" " track " "journal should include track event"
}

case_080_journal_empty() {
  local file
  file="$(make_note_file "note.txt" $'first version\n')"
  run_omohi_capture track "$file"
  assert_eq "0" "$RUN_CODE" "track should succeed"
  rm -rf "$HOME_DIR/.omohi/journal"
  mkdir -p "$HOME_DIR/.omohi/journal"

  run_omohi_capture journal
  assert_eq "0" "$RUN_CODE" "journal should succeed"
  assert_contains "$RUN_STDOUT" "no journal entries" "journal should report empty state"
}

case_081_journal_rejects_extra_args() {
  run_omohi_capture journal extra
  assert_eq "2" "$RUN_CODE" "journal should reject extra args"
  assert_contains "$RUN_STDERR" "Unexpected argument." "journal should report usage error"
}

case_082_tag_ls_with_tags() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture tag ls "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "tag ls should succeed"
  assert_contains "$RUN_STDOUT" "Found 2 tag(s) for commit $LAST_COMMIT_ID." "tag ls should report count"
  assert_contains "$RUN_STDOUT" "alpha" "tag ls should include alpha tag"
  assert_contains "$RUN_STDOUT" "beta" "tag ls should include beta tag"
}

case_083_tag_ls_without_tags() {
  setup_commit_without_tags
  run_omohi_capture tag ls "$LAST_COMMIT_ID"
  assert_eq "0" "$RUN_CODE" "tag ls should succeed"
  assert_contains "$RUN_STDOUT" "Found 0 tag(s) for commit $LAST_COMMIT_ID." "tag ls should report zero tags"
  assert_contains "$RUN_STDOUT" "(none)" "tag ls should show none"
}

case_084_tag_ls_unknown_commit() {
  setup_commit_without_tags
  run_omohi_capture tag ls 0000000000000000000000000000000000000000000000000000000000000000
  assert_eq "4" "$RUN_CODE" "tag ls should fail for unknown commit"
  assert_contains "$RUN_STDERR" "Commit not found:" "tag ls should report unknown commit"
}

case_085_tag_add_single() {
  setup_commit_without_tags
  run_omohi_capture tag add "$LAST_COMMIT_ID" release
  assert_eq "0" "$RUN_CODE" "tag add should succeed"
  assert_contains "$RUN_STDOUT" "Added 1 tag(s) to commit $LAST_COMMIT_ID." "tag add should report added tag"
  assert_contains "$RUN_STDOUT" "release" "tag add should list resulting tags"
}

case_086_tag_add_multiple() {
  setup_commit_without_tags
  run_omohi_capture tag add "$LAST_COMMIT_ID" release prod
  assert_eq "0" "$RUN_CODE" "tag add should succeed for multiple tags"
  assert_contains "$RUN_STDOUT" "Added 2 tag(s) to commit $LAST_COMMIT_ID." "tag add should report count"
  assert_contains "$RUN_STDOUT" "release" "tag add should include release tag"
  assert_contains "$RUN_STDOUT" "prod" "tag add should include prod tag"
}

case_087_tag_add_existing_only() {
  setup_commit_without_tags
  run_omohi_capture tag add "$LAST_COMMIT_ID" release
  assert_eq "0" "$RUN_CODE" "first tag add should succeed"

  run_omohi_capture tag add "$LAST_COMMIT_ID" release
  assert_eq "0" "$RUN_CODE" "re-adding same tag should succeed"
  assert_contains "$RUN_STDOUT" "No new tags were added; commit $LAST_COMMIT_ID already has the specified tags." "tag add should report no-op"
}

case_088_tag_add_unknown_commit() {
  setup_commit_without_tags
  run_omohi_capture tag add 0000000000000000000000000000000000000000000000000000000000000000 release
  assert_eq "4" "$RUN_CODE" "tag add should fail for unknown commit"
  assert_contains "$RUN_STDERR" "Commit not found:" "tag add should report unknown commit"
}

case_089_tag_add_invalid_name() {
  setup_commit_without_tags
  run_omohi_capture tag add "$LAST_COMMIT_ID" ""
  assert_eq "3" "$RUN_CODE" "tag add should reject empty tag"
  assert_contains "$RUN_STDERR" "unexpected system error" "tag add invalid tag currently uses generic runtime message"
}

case_090_tag_rm_single() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture tag rm "$LAST_COMMIT_ID" alpha
  assert_eq "0" "$RUN_CODE" "tag rm should succeed"
  assert_contains "$RUN_STDOUT" "Removed 1 tag(s) from commit $LAST_COMMIT_ID." "tag rm should report removed count"
  assert_contains "$RUN_STDOUT" "beta" "tag rm should list remaining tags"
}

case_091_tag_rm_multiple() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture tag rm "$LAST_COMMIT_ID" alpha beta
  assert_eq "0" "$RUN_CODE" "tag rm should succeed for multiple tags"
  assert_contains "$RUN_STDOUT" "Removed 2 tag(s) from commit $LAST_COMMIT_ID." "tag rm should report removed count"
}

case_092_tag_rm_no_tags() {
  setup_commit_without_tags
  run_omohi_capture tag rm "$LAST_COMMIT_ID" release
  assert_eq "0" "$RUN_CODE" "tag rm should succeed for tagless commit"
  assert_contains "$RUN_STDOUT" "Commit $LAST_COMMIT_ID has no tags to remove." "tag rm should report no tags"
  assert_contains "$RUN_STDOUT" "(none)" "tag rm should show empty result"
}

case_093_tag_rm_no_matching_tags() {
  setup_commit_with_two_files_and_tags
  run_omohi_capture tag rm "$LAST_COMMIT_ID" release
  assert_eq "0" "$RUN_CODE" "tag rm should succeed for no-op removal"
  assert_contains "$RUN_STDOUT" "No matching tags found to remove from commit $LAST_COMMIT_ID." "tag rm should report no matching tags"
  assert_contains "$RUN_STDOUT" "alpha" "tag rm should still show alpha tag"
  assert_contains "$RUN_STDOUT" "beta" "tag rm should still show beta tag"
}

case_094_tag_rm_unknown_commit() {
  setup_commit_without_tags
  run_omohi_capture tag rm 0000000000000000000000000000000000000000000000000000000000000000 release
  assert_eq "4" "$RUN_CODE" "tag rm should fail for unknown commit"
  assert_contains "$RUN_STDERR" "Commit not found:" "tag rm should report unknown commit"
}

case_095_tag_rm_invalid_name() {
  local long_tag
  long_tag="$(make_long_tag)"
  setup_commit_without_tags
  run_omohi_capture tag rm "$LAST_COMMIT_ID" "$long_tag"
  assert_eq "0" "$RUN_CODE" "tag rm currently accepts too-long names as a no-op when no tags exist"
  assert_contains "$RUN_STDOUT" "Commit $LAST_COMMIT_ID has no tags to remove." "tag rm should report no tags to remove"
}

case_096_help_default() {
  run_omohi_capture help
  assert_eq "0" "$RUN_CODE" "help should succeed"
  assert_contains "$RUN_STDOUT" "omohi commands:" "help should list commands"
}

case_097_help_topic_ignored() {
  run_omohi_capture help commit
  assert_eq "0" "$RUN_CODE" "help with topic should succeed"
  assert_contains "$RUN_STDOUT" "omohi commands:" "help topic should return command list"
}

case_098_help_short_alias() {
  run_omohi_capture -h
  assert_eq "0" "$RUN_CODE" "help short alias should succeed"
  assert_contains "$RUN_STDOUT" "omohi commands:" "help short alias should match help output"
}

case_099_help_long_alias() {
  run_omohi_capture --help
  assert_eq "0" "$RUN_CODE" "help long alias should succeed"
  assert_contains "$RUN_STDOUT" "omohi commands:" "help long alias should match help output"
}

case_100_help_too_many_topics() {
  run_omohi_capture help commit extra
  assert_eq "2" "$RUN_CODE" "help should reject too many topics"
  assert_contains "$RUN_STDERR" "Unexpected argument." "help should report usage error"
}

run_case "track single file" case_001_track_single_file
run_case "track multiple files" case_002_track_multiple_files
run_case "track directory recursive" case_003_track_directory_recursive
run_case "track already tracked file" case_004_track_already_tracked
run_case "track skips non-regular entries" case_005_track_directory_skips_non_regular
run_case "track missing path" case_006_track_missing_path
run_case "untrack by tracked id" case_007_untrack_by_id
run_case "untrack missing batch" case_008_untrack_missing_batch
run_case "untrack missing none" case_009_untrack_missing_none
run_case "untrack missing with positional" case_010_untrack_missing_with_positional
run_case "untrack missing with value" case_011_untrack_missing_with_value
run_case "untrack unknown id" case_012_untrack_unknown_id
run_case "add single tracked file" case_013_add_single_tracked_file
run_case "add multiple tracked files" case_014_add_multiple_tracked_files
run_case "add directory recursive" case_015_add_directory_recursive
run_case "add all short option" case_016_add_all_short_option
run_case "add all long option" case_017_add_all_long_option
run_case "add already staged file" case_018_add_already_staged
run_case "add unchanged tracked file" case_019_add_unchanged_tracked_file
run_case "add missing tracked file" case_020_add_missing_tracked_file
run_case "add untracked path" case_021_add_untracked_path
run_case "add all with path" case_022_add_all_with_path
run_case "add all with value" case_023_add_all_with_value
run_case "add positional after double dash" case_024_add_double_dash_positional
run_case "rm single staged file" case_025_rm_single_staged_file
run_case "rm multiple staged files" case_026_rm_multiple_staged_files
run_case "rm directory recursive" case_027_rm_directory_recursive
run_case "rm tracked but not staged" case_028_rm_tracked_but_not_staged
run_case "rm untracked path" case_029_rm_untracked_path
run_case "rm mixed staged and non-staged" case_030_rm_mixed_with_non_staged
run_case "rm all short option" case_030_rm_all_short_option
run_case "rm all long option with deleted source" case_030_rm_all_long_option_with_deleted_source
run_case "rm all mixed with path" case_030_rm_all_mixed_with_path
run_case "rm all with value" case_030_rm_all_with_value
run_case "rm positional after double dash" case_030_rm_double_dash_positional
run_case "commit short message option" case_031_commit_short_message_option
run_case "commit long message option" case_032_commit_long_message_option
run_case "commit with multiple tags" case_033_commit_with_multiple_tags
run_case "commit dry-run" case_034_commit_dry_run
run_case "commit dry-run marks missing" case_035_commit_dry_run_marks_missing
run_case "commit requires message" case_036_commit_requires_message
run_case "commit requires staged files" case_037_commit_requires_staged_files
run_case "commit uppercase option keys" case_038_commit_uppercase_option_keys
run_case "commit rejects extra args after double dash" case_039_commit_double_dash_extra_args
run_case "status clean" case_040_status_clean
run_case "status staged only" case_041_status_staged_only
run_case "status changed only" case_042_status_changed_only
run_case "status missing only" case_043_status_missing_only
run_case "status staged and changed" case_044_status_staged_and_changed
run_case "status staged and missing" case_045_status_staged_and_missing
run_case "status changed and missing" case_046_status_changed_and_missing
run_case "status staged changed missing" case_047_status_staged_changed_missing
run_case "status tty colors" case_048_status_tty_colors
run_case "tracklist default text" case_049_tracklist_text_default
run_case "tracklist empty" case_050_tracklist_empty
run_case "tracklist json output" case_051_tracklist_json_output
run_case "tracklist id field" case_052_tracklist_field_id_only
run_case "tracklist id and path fields" case_053_tracklist_field_id_path
run_case "tracklist json with fields" case_054_tracklist_json_with_fields
run_case "tracklist unknown field" case_055_tracklist_unknown_field
run_case "version command" case_056_version_command
run_case "version short alias" case_057_version_short_alias
run_case "version long alias" case_058_version_long_alias
run_case "version rejects extra args" case_059_version_rejects_extra_args
run_case "find all commits text" case_060_find_all_commits_text
run_case "find by tag" case_061_find_by_tag
run_case "find by since" case_062_find_by_since
run_case "find by tag and range" case_063_find_by_tag_and_range
run_case "find empty" case_064_find_empty
run_case "find json output" case_065_find_json_output
run_case "find text fields" case_066_find_text_fields
run_case "find json with fields" case_067_find_json_with_fields
run_case "find unknown field" case_068_find_unknown_field
run_case "find invalid date" case_069_find_invalid_date
run_case "find uppercase option keys" case_070_find_uppercase_option_keys
run_case "find rejects extra args after double dash" case_071_find_double_dash_extra_args
run_case "show default text" case_072_show_text_default
run_case "show without tags" case_073_show_without_tags
run_case "show json output" case_074_show_json_output
run_case "show text fields" case_075_show_text_fields
run_case "show options before positional" case_076_show_options_before_positional
run_case "show unknown field" case_077_show_unknown_field
run_case "show unknown commit" case_078_show_unknown_commit
run_case "journal non-empty" case_079_journal_non_empty
run_case "journal empty" case_080_journal_empty
run_case "journal rejects extra args" case_081_journal_rejects_extra_args
run_case "tag ls with tags" case_082_tag_ls_with_tags
run_case "tag ls without tags" case_083_tag_ls_without_tags
run_case "tag ls unknown commit" case_084_tag_ls_unknown_commit
run_case "tag add single" case_085_tag_add_single
run_case "tag add multiple" case_086_tag_add_multiple
run_case "tag add existing only" case_087_tag_add_existing_only
run_case "tag add unknown commit" case_088_tag_add_unknown_commit
run_case "tag add invalid name" case_089_tag_add_invalid_name
run_case "tag rm single" case_090_tag_rm_single
run_case "tag rm multiple" case_091_tag_rm_multiple
run_case "tag rm no tags" case_092_tag_rm_no_tags
run_case "tag rm no matching tags" case_093_tag_rm_no_matching_tags
run_case "tag rm unknown commit" case_094_tag_rm_unknown_commit
run_case "tag rm invalid name" case_095_tag_rm_invalid_name
run_case "help default" case_096_help_default
run_case "help topic ignored" case_097_help_topic_ignored
run_case "help short alias" case_098_help_short_alias
run_case "help long alias" case_099_help_long_alias
run_case "help too many topics" case_100_help_too_many_topics

printf 'Completed %d e2e matrix cases.\n' "$CASE_COUNTER"
