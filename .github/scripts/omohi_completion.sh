#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
COMPLETION_FILE="${ROOT_DIR}/completions/omohi.bash"

if ! command -v bash >/dev/null 2>&1; then
  echo "bash is required" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" COMPLETION_FILE="${COMPLETION_FILE}" bash <<'EOF'
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-}"
COMPLETION_FILE="${COMPLETION_FILE:-}"
source "${COMPLETION_FILE}"

assert_reply() {
  local expected="$1"
  shift

  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()

  _omohi_complete

  local actual="${COMPREPLY[*]-}"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "completion mismatch" >&2
    echo "  words: ${COMP_WORDS[*]}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

assert_reply "track untrack add rm commit status tracklist version find show tag help -h --help -v --version" omohi ""
assert_reply "ls add rm" omohi tag ""
assert_reply "-m --message -t --tag --dry-run" omohi commit ""
assert_reply "--message" omohi commit --m
assert_reply "-t --tag -d --date" omohi find ""
assert_reply "--date" omohi find --d
assert_reply "" omohi status ""
assert_reply "" omohi show ""
assert_reply "" omohi commit --message ""
EOF
