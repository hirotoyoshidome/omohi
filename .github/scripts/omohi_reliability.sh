#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <omohi-binary>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.github/scripts/omohi_test_lib.sh
source "$SCRIPT_DIR/omohi_test_lib.sh"

init_omohi_test_env "$1" "omohi-reliability"

NOTE_PATH="$(make_note_file "note.txt" $'first version\n')"

run_omohi_capture track "$NOTE_PATH"
assert_eq "0" "$RUN_CODE" "track should succeed"

printf 'stale lock\n' > "$HOME_DIR/.omohi/LOCK"
run_omohi_capture add "$NOTE_PATH"
assert_eq "4" "$RUN_CODE" "stale LOCK should block mutating commands"
assert_contains "$RUN_STDERR" "remove ~/.omohi/LOCK manually" "LOCK guidance should mention manual cleanup"
rm -f "$HOME_DIR/.omohi/LOCK"

run_omohi_capture add "$NOTE_PATH"
assert_eq "0" "$RUN_CODE" "add should succeed after lock cleanup"

STAGED_OBJECT_NAME="$(find "$HOME_DIR/.omohi/staged/objects" -type f -maxdepth 1 -mindepth 1 -exec basename {} \;)"
if [ -z "$STAGED_OBJECT_NAME" ]; then
  echo "expected a staged object after add" >&2
  exit 1
fi
rm -f "$HOME_DIR/.omohi/staged/objects/$STAGED_OBJECT_NAME"

run_omohi_capture commit -m "missing object"
assert_eq "10" "$RUN_CODE" "missing staged object should be treated as a system error"
assert_contains "$RUN_STDERR" "unexpected system error" "missing staged object currently maps to generic system guidance"
assert_file_missing "$HOME_DIR/.omohi/HEAD" "HEAD must not be written on missing staged object"

run_omohi_capture add "$NOTE_PATH"
assert_eq "0" "$RUN_CODE" "re-staging after a missing object failure should succeed"

STAGED_ENTRY_PATH="$(find "$HOME_DIR/.omohi/staged/entries" -type f -maxdepth 1 -mindepth 1 | head -n 1)"
assert_file_exists "$STAGED_ENTRY_PATH" "staged entry should exist after add"
printf 'contentHash=broken\n' > "$STAGED_ENTRY_PATH"

run_omohi_capture commit -m "broken entry"
assert_eq "3" "$RUN_CODE" "broken staged entry should be a domain error"
assert_contains "$RUN_STDERR" "unexpected system error" "invalid staged entry currently maps to generic runtime guidance"
assert_file_missing "$HOME_DIR/.omohi/HEAD" "HEAD must remain absent after broken staged entry"

run_omohi_capture add "$NOTE_PATH"
assert_eq "0" "$RUN_CODE" "restaging after entry corruption should succeed"

run_omohi_capture commit -m "recovered"
assert_eq "0" "$RUN_CODE" "commit should recover after restaging"
assert_contains "$RUN_STDOUT" "Committed " "successful commit output should include commit id"
assert_file_exists "$HOME_DIR/.omohi/HEAD" "HEAD should be present after successful recovery commit"
