#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <omohi-binary>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.github/scripts/omohi_test_lib.sh
source "$SCRIPT_DIR/omohi_test_lib.sh"

init_omohi_test_env "$1" "omohi-contract"

NOTE_PATH="$(make_note_file "note.txt" $'first version\n')"

run_omohi_capture version
assert_eq "0" "$RUN_CODE" "version should succeed"
assert_contains "$RUN_STDOUT" "omohi version " "version output should include prefix"

run_omohi_capture invalid-command
assert_eq "2" "$RUN_CODE" "invalid command should be usage error"
assert_contains "$RUN_STDERR" "Invalid command." "invalid command message should be stable"

run_omohi_capture commit
assert_eq "2" "$RUN_CODE" "missing commit message should be usage error"
assert_contains "$RUN_STDERR" "Missing required argument." "missing argument guidance should be stable"

run_omohi_capture status
assert_eq "4" "$RUN_CODE" "status before initialization should be use-case error"
assert_contains "$RUN_STDERR" "Store is not initialized." "not initialized guidance should be stable"

run_omohi_capture track "$NOTE_PATH"
assert_eq "0" "$RUN_CODE" "track should initialize store"

run_omohi_capture show short
assert_eq "3" "$RUN_CODE" "invalid commit id should be domain error"
assert_contains "$RUN_STDERR" "unexpected system error" "domain errors currently use generic runtime message"

printf '999\n' > "$HOME_DIR/.omohi/VERSION"
run_omohi_capture status
assert_eq "10" "$RUN_CODE" "version mismatch should be system error"
assert_contains "$RUN_STDERR" "Store version mismatch detected" "version mismatch guidance should be stable"

printf '1\n' > "$HOME_DIR/.omohi/VERSION"
rm -f "$HOME_DIR/.omohi/VERSION"
run_omohi_capture status
assert_eq "11" "$RUN_CODE" "missing VERSION should be data-destroyed error"
assert_contains "$RUN_STDERR" "Store metadata is incomplete" "missing VERSION guidance should be stable"
