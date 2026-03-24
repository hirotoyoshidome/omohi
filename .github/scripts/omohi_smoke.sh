#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <omohi-binary>" >&2
  exit 2
fi

OMOHI_BIN="$1"

if [ ! -x "$OMOHI_BIN" ]; then
  echo "omohi binary is not executable: $OMOHI_BIN" >&2
  exit 1
fi

HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omohi-home.XXXXXX")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omohi-work.XXXXXX")"

cleanup() {
  rm -rf "$HOME_DIR" "$WORK_DIR"
}

trap cleanup EXIT

TEST_FILE="$WORK_DIR/note.txt"
printf 'first version\n' > "$TEST_FILE"
ABS_PATH="$(cd "$WORK_DIR" && pwd)/note.txt"

run_omohi() {
  HOME="$HOME_DIR" "$OMOHI_BIN" "$@"
}

run_omohi help
run_omohi version
run_omohi track "$ABS_PATH"
run_omohi tracklist
run_omohi add "$ABS_PATH"
run_omohi status

COMMIT_OUTPUT="$(run_omohi commit -m "smoke commit")"
printf '%s\n' "$COMMIT_OUTPUT"

COMMIT_ID="$(printf '%s\n' "$COMMIT_OUTPUT" | sed -n 's/^Committed \([0-9a-f]\{64\}\)\.$/\1/p')"

if [ -z "$COMMIT_ID" ]; then
  echo "failed to extract commit id from commit output" >&2
  exit 1
fi

run_omohi find
run_omohi show "$COMMIT_ID"
run_omohi tag add "$COMMIT_ID" smoke basic
run_omohi tag ls "$COMMIT_ID"
run_omohi tag rm "$COMMIT_ID" basic

exit 0
