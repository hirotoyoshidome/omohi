#!/usr/bin/env bash

set -euo pipefail

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "assert_eq failed: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "assert_contains failed: $message" >&2
    echo "  needle: $needle" >&2
    echo "  haystack: $haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "assert_not_contains failed: $message" >&2
    echo "  needle: $needle" >&2
    echo "  haystack: $haystack" >&2
    exit 1
  fi
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  local message="$3"

  if ! printf '%s' "$haystack" | grep -Eq "$pattern"; then
    echo "assert_matches failed: $message" >&2
    echo "  pattern: $pattern" >&2
    echo "  haystack: $haystack" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  local message="$2"

  if [ ! -e "$path" ]; then
    echo "assert_file_exists failed: $message ($path)" >&2
    exit 1
  fi
}

assert_file_missing() {
  local path="$1"
  local message="$2"

  if [ -e "$path" ]; then
    echo "assert_file_missing failed: $message ($path)" >&2
    exit 1
  fi
}

init_omohi_test_env() {
  if [ "$#" -ne 2 ]; then
    echo "usage: init_omohi_test_env <omohi-binary> <prefix>" >&2
    exit 2
  fi

  OMOHI_BIN="$1"
  TEST_PREFIX="$2"

  if [ ! -x "$OMOHI_BIN" ]; then
    echo "omohi binary is not executable: $OMOHI_BIN" >&2
    exit 1
  fi

  TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${TEST_PREFIX}.XXXXXX")"
  TEST_TMP_ROOT="$(printf '%s' "$TEST_TMP_ROOT" | sed 's://*:/:g')"
  HOME_DIR="$TEST_TMP_ROOT/home"
  WORK_DIR="$TEST_TMP_ROOT/work"
  mkdir -p "$HOME_DIR" "$WORK_DIR"

  cleanup_omohi_test_env() {
    rm -rf "$TEST_TMP_ROOT"
  }

  trap cleanup_omohi_test_env EXIT
}

reset_omohi_test_env() {
  rm -rf "$HOME_DIR" "$WORK_DIR"
  mkdir -p "$HOME_DIR" "$WORK_DIR"
}

make_note_file() {
  local relative_name="$1"
  local body="$2"
  local path="$WORK_DIR/$relative_name"

  mkdir -p "$(dirname "$path")"
  printf '%s' "$body" > "$path"
  printf '%s\n' "$(printf '%s' "$path" | sed 's://*:/:g')"
}

run_omohi_capture() {
  RUN_STDOUT_FILE="$TEST_TMP_ROOT/stdout.txt"
  RUN_STDERR_FILE="$TEST_TMP_ROOT/stderr.txt"

  set +e
  HOME="$HOME_DIR" "$OMOHI_BIN" "$@" >"$RUN_STDOUT_FILE" 2>"$RUN_STDERR_FILE"
  RUN_CODE=$?
  set -e

  RUN_STDOUT="$(cat "$RUN_STDOUT_FILE")"
  RUN_STDERR="$(cat "$RUN_STDERR_FILE")"
}

# Builds a shell-safe command line for invoking omohi under a pseudo terminal.
build_omohi_tty_command() {
  local command
  command="$(printf 'HOME=%q %q' "$HOME_DIR" "$OMOHI_BIN")"

  while [ "$#" -gt 0 ]; do
    command="${command} $(printf '%q' "$1")"
    shift
  done

  printf '%s\n' "$command"
}

run_omohi_capture_tty() {
  RUN_STDOUT_FILE="$TEST_TMP_ROOT/stdout.txt"
  RUN_STDERR_FILE="$TEST_TMP_ROOT/stderr.txt"

  set +e
  if script --version >/dev/null 2>&1; then
    local command
    command="$(build_omohi_tty_command "$@")"
    script -q -e -c "$command" /dev/null >"$RUN_STDOUT_FILE" 2>"$RUN_STDERR_FILE"
  else
    script -q /dev/null env HOME="$HOME_DIR" "$OMOHI_BIN" "$@" >"$RUN_STDOUT_FILE" 2>"$RUN_STDERR_FILE"
  fi
  RUN_CODE=$?
  set -e

  RUN_STDOUT="$(tr -d '\r' <"$RUN_STDOUT_FILE")"
  RUN_STDERR="$(cat "$RUN_STDERR_FILE")"
}
