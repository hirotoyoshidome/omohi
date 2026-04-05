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
TEST_BIN_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_BIN_DIR}"' EXIT
FAKE_OMOHI="${TEST_BIN_DIR}/omohi"
cat > "${FAKE_OMOHI}" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" != "__complete" ]]; then
  exit 1
fi

shift
if [[ "${1-}" != "--index" ]]; then
  exit 1
fi
index="${2-}"
shift 2
if [[ "${1-}" != "--" ]]; then
  exit 1
fi
shift

case "$*" in
  "omohi " )
    printf '%s\n' track untrack add rm commit status tracklist version find show tag help -h --help -v --version
    ;;
  "omohi tag " )
    printf '%s\n' ls add rm
    ;;
  "omohi commit " )
    printf '%s\n' -m --message -t --tag --dry-run
    ;;
  "omohi commit --m" )
    printf '%s\n' --message
    ;;
  "omohi add " )
    printf '%s\n' -a --all
    ;;
  "omohi add -" )
    printf '%s\n' -a --all
    ;;
  "omohi add --" )
    printf '%s\n' --all
    ;;
  "omohi find " )
    printf '%s\n' -t --tag -d --date
    ;;
  "omohi find --d" )
    printf '%s\n' --date
    ;;
  "omohi tracklist " )
    printf '%s\n' --output --field
    ;;
  "omohi tracklist --o" )
    printf '%s\n' --output
    ;;
  "omohi tracklist --output " )
    printf '%s\n' text json
    ;;
  "omohi tracklist --field " )
    printf '%s\n' id path
    ;;
  "omohi untrack " )
    printf '%s\n' 11111111111111111111111111111111 22222222222222222222222222222222
    ;;
  "omohi show " )
    printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    ;;
  "omohi tag add aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa " )
    printf '%s\n' prod release
    ;;
  "omohi tag rm aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa " )
    printf '%s\n' prod release
    ;;
  "omohi find --tag " )
    printf '%s\n' prod release
    ;;
esac
SCRIPT
chmod +x "${FAKE_OMOHI}"
export OMOHI_COMPLETION_COMMAND="${FAKE_OMOHI}"
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
assert_reply "-a --all" omohi add -
assert_reply "--all" omohi add --
assert_reply "-t --tag -d --date" omohi find ""
assert_reply "--date" omohi find --d
assert_reply "--output --field" omohi tracklist ""
assert_reply "--output" omohi tracklist --o
assert_reply "text json" omohi tracklist --output ""
assert_reply "id path" omohi tracklist --field ""
assert_reply "" omohi status ""
assert_reply "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" omohi show ""
assert_reply "" omohi commit --message ""
assert_reply "11111111111111111111111111111111 22222222222222222222222222222222" omohi untrack ""
assert_reply "prod release" omohi tag add aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ""
assert_reply "prod release" omohi tag rm aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ""
assert_reply "prod release" omohi find --tag ""
EOF
