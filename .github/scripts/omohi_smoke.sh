#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <omohi-binary>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.github/scripts/omohi_test_lib.sh
source "$SCRIPT_DIR/omohi_test_lib.sh"

init_omohi_test_env "$1" "omohi-smoke"

TEST_FILE="$WORK_DIR/note.txt"
printf 'first version\n' > "$TEST_FILE"
ABS_PATH="$(cd "$WORK_DIR" && pwd)/note.txt"

run_omohi_capture help
assert_eq "0" "$RUN_CODE" "help should succeed"
assert_contains "$RUN_STDOUT" "omohi commands:" "help output should list commands"

run_omohi_capture version
assert_eq "0" "$RUN_CODE" "version should succeed"
assert_contains "$RUN_STDOUT" "omohi version " "version output should include prefix"

run_omohi_capture track "$ABS_PATH"
assert_eq "0" "$RUN_CODE" "track should succeed"
assert_contains "$RUN_STDOUT" "Tracked: $ABS_PATH" "track should report the tracked file"

run_omohi_capture tracklist
assert_eq "0" "$RUN_CODE" "tracklist should succeed"
assert_matches "$RUN_STDOUT" "^[0-9a-f]{32} ${ABS_PATH}$" "tracklist should show tracked id and path"

run_omohi_capture add "$ABS_PATH"
assert_eq "0" "$RUN_CODE" "add should succeed"
assert_contains "$RUN_STDOUT" "Staged: $ABS_PATH" "add should report the staged file"

run_omohi_capture status
assert_eq "0" "$RUN_CODE" "status should succeed"
assert_contains "$RUN_STDOUT" "staged: $ABS_PATH" "status should show staged file"

run_omohi_capture commit -m "smoke commit"
assert_eq "0" "$RUN_CODE" "commit should succeed"
printf '%s\n' "$RUN_STDOUT"

COMMIT_ID="$(printf '%s\n' "$RUN_STDOUT" | sed -n 's/^Committed \([0-9a-f]\{64\}\)\.$/\1/p')"
if [ -z "$COMMIT_ID" ]; then
  echo "failed to extract commit id from commit output" >&2
  exit 1
fi

printf 'second version\n' > "$TEST_FILE"

run_omohi_capture status
assert_eq "0" "$RUN_CODE" "status should succeed after file update"
assert_contains "$RUN_STDOUT" "changed: $ABS_PATH" "status should show changed file after edit"

run_omohi_capture add "$ABS_PATH"
assert_eq "0" "$RUN_CODE" "restaging should succeed"
assert_contains "$RUN_STDOUT" "Staged: $ABS_PATH" "restaging should report the file"

run_omohi_capture find
assert_eq "0" "$RUN_CODE" "find should succeed"
assert_contains "$RUN_STDOUT" "Found 1 commit(s)." "find should report one commit"
assert_contains "$RUN_STDOUT" "$COMMIT_ID" "find should include commit id"

run_omohi_capture show "$COMMIT_ID"
assert_eq "0" "$RUN_CODE" "show should succeed"
assert_contains "$RUN_STDOUT" "Found commit $COMMIT_ID" "show should report commit header"
assert_contains "$RUN_STDOUT" "smoke commit" "show should include commit message"

run_omohi_capture tag add "$COMMIT_ID" smoke basic
assert_eq "0" "$RUN_CODE" "tag add should succeed"
assert_contains "$RUN_STDOUT" "Added 2 tag(s) to commit $COMMIT_ID." "tag add should report both tags"

run_omohi_capture tag ls "$COMMIT_ID"
assert_eq "0" "$RUN_CODE" "tag ls should succeed"
assert_contains "$RUN_STDOUT" "Found 2 tag(s) for commit $COMMIT_ID." "tag ls should report both tags"
assert_contains "$RUN_STDOUT" "smoke" "tag ls should list smoke tag"
assert_contains "$RUN_STDOUT" "basic" "tag ls should list basic tag"

run_omohi_capture tag rm "$COMMIT_ID" basic
assert_eq "0" "$RUN_CODE" "tag rm should succeed"
assert_contains "$RUN_STDOUT" "Removed 1 tag(s) from commit $COMMIT_ID." "tag rm should report removed tag"
assert_contains "$RUN_STDOUT" "smoke" "tag rm output should retain remaining tag"

exit 0
