#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <omohi-binary>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.github/scripts/omohi_test_lib.sh
source "$SCRIPT_DIR/omohi_test_lib.sh"

init_omohi_test_env "$1" "omohi-perf"

REPORT_PATH="$TEST_TMP_ROOT/perf-baseline.txt"
export REPORT_PATH

compute_content_hash() {
  python3 -c 'import base64, hashlib, sys; data=sys.argv[1].encode(); print(hashlib.sha256(base64.b64encode(data)).hexdigest())' "$1"
}

write_commit_file() {
  local root="$1"
  local commit_id="$2"
  local snapshot_id="$3"
  local message="$4"
  local created_at="$5"
  local prefix="${commit_id:0:2}"

  mkdir -p "$root/commits/$prefix"
  cat > "$root/commits/$prefix/$commit_id" <<EOF
snapshotId=$snapshot_id
message=$message
createdAt=$created_at
EOF
}

# Generates the large find baseline fixture in one Python process to avoid shell-loop overhead.
generate_find_fixture() {
  local root="$1"
  local snapshot_id="$2"

  python3 - "$root" "$snapshot_id" <<'PY'
import os
import sys

root = sys.argv[1]
snapshot_id = sys.argv[2]
commits_root = os.path.join(root, "commits")
os.makedirs(commits_root, exist_ok=True)

for prefix in [f"{value:02x}" for value in range(256)]:
    os.makedirs(os.path.join(commits_root, prefix), exist_ok=True)

for i in range(10000):
    commit_id = f"{i:064x}"
    created_at = f"2026-03-{i % 28 + 1:02d}T00:00:{i % 60:02d}.000Z"
    path = os.path.join(commits_root, commit_id[:2], commit_id)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            f"snapshotId={snapshot_id}\n"
            f"message=bench-find-{i}\n"
            f"createdAt={created_at}\n"
        )
PY
}

setup_find_fixture() {
  local home_dir="$1"
  local root="$home_dir/.omohi"
  local snapshot_id

  mkdir -p "$root"
  printf '1\n' > "$root/VERSION"
  snapshot_id="$(printf 'a%.0s' $(seq 1 64))"
  generate_find_fixture "$root" "$snapshot_id"
}

setup_status_fixture() {
  local home_dir="$1"
  local work_dir="$2"
  local root="$home_dir/.omohi"
  local payload=$'status payload\n'
  local content_hash
  local object_path
  local snapshot_id
  local commit_id
  local i
  local file_path
  local tracked_id

  mkdir -p "$root/tracked" "$root/tracked/.trash"
  printf '1\n' > "$root/VERSION"

  content_hash="$(compute_content_hash "$payload")"
  object_path="$root/objects/${content_hash:0:2}/$content_hash"
  mkdir -p "$(dirname "$object_path")"
  printf '%s' "$payload" > "$object_path"

  mkdir -p "$work_dir/status"
  for i in $(seq 0 999); do
    file_path="$work_dir/status/file-$i.txt"
    printf '%s' "$payload" > "$file_path"
    tracked_id="$(printf '%032x' "$i")"
    printf '%s' "$file_path" > "$root/tracked/$tracked_id"
  done

  snapshot_id="$(printf 'c%.0s' $(seq 1 64))"
  commit_id="$(printf 'b%.0s' $(seq 1 64))"
  mkdir -p "$root/snapshots/${snapshot_id:0:2}"
  printf 'entries=/objects/%s/%s:%s\n' "${content_hash:0:2}" "$content_hash" "$content_hash" > "$root/snapshots/${snapshot_id:0:2}/$snapshot_id"
  write_commit_file "$root" "$commit_id" "$snapshot_id" "bench-status" "2026-03-24T00:00:00.000Z"
  printf '%s\n' "$commit_id" > "$root/HEAD"
}

setup_commit_fixture() {
  local home_dir="$1"
  local root="$home_dir/.omohi"
  local i
  local content_hash
  local entry_path
  local object_path
  local staged_path

  mkdir -p "$root/staged/entries" "$root/staged/objects"
  printf '1\n' > "$root/VERSION"

  for i in $(seq 0 99); do
    content_hash="$(printf '%064x' "$((i + 1))")"
    entry_path="$root/staged/entries/entry-$i"
    object_path="$root/staged/objects/$content_hash"
    staged_path="/tmp/omohi-perf-commit-$i.txt"
    cat > "$entry_path" <<EOF
path=$staged_path
trackedFileId=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
contentHash=$content_hash
EOF
    printf 'payload-%s\n' "$i" > "$object_path"
  done
}

measure_command() {
  local label="$1"
  local home_dir="$2"
  shift 2

  local stderr_file="$TEST_TMP_ROOT/$label.stderr"
  local elapsed_sec rss_kb

  if command -v gtime >/dev/null 2>&1 && gtime --version >/dev/null 2>&1; then
    local time_file="$TEST_TMP_ROOT/$label.time"
    gtime -f '%e %M' -o "$time_file" env HOME="$home_dir" "$OMOHI_BIN" "$@" >/dev/null 2>"$stderr_file"
    local stats
    stats="$(cat "$time_file")"
    elapsed_sec="${stats%% *}"
    rss_kb="${stats##* }"
  elif [ -x /usr/bin/time ] && /usr/bin/time -f '%e %M' true >/dev/null 2>&1; then
    local time_file="$TEST_TMP_ROOT/$label.time"
    /usr/bin/time -f '%e %M' -o "$time_file" env HOME="$home_dir" "$OMOHI_BIN" "$@" >/dev/null 2>"$stderr_file"
    local stats
    stats="$(cat "$time_file")"
    elapsed_sec="${stats%% *}"
    rss_kb="${stats##* }"
  else
    local start end
    start="$(python3 -c 'import time; print(time.time())')"
    env HOME="$home_dir" "$OMOHI_BIN" "$@" >/dev/null 2>"$stderr_file"
    end="$(python3 -c 'import time; print(time.time())')"
    elapsed_sec="$(python3 -c 'import sys; print(f"{float(sys.argv[2]) - float(sys.argv[1]):.3f}")' "$start" "$end")"
    rss_kb="na"
  fi

  printf '%s elapsed_seconds=%s max_rss_kb=%s\n' "$label" "$elapsed_sec" "$rss_kb" | tee -a "$REPORT_PATH"
}

FIND_HOME="$TEST_TMP_ROOT/find-home"
STATUS_HOME="$TEST_TMP_ROOT/status-home"
COMMIT_HOME="$TEST_TMP_ROOT/commit-home"
mkdir -p "$FIND_HOME" "$STATUS_HOME" "$COMMIT_HOME"
: > "$REPORT_PATH"

setup_find_fixture "$FIND_HOME"
setup_status_fixture "$STATUS_HOME" "$WORK_DIR"
setup_commit_fixture "$COMMIT_HOME"

measure_command "find_10000_commits" "$FIND_HOME" find
measure_command "status_1000_tracked" "$STATUS_HOME" status
measure_command "tracklist_1000_tracked" "$STATUS_HOME" tracklist
measure_command "commit_100_staged" "$COMMIT_HOME" commit -m "bench"
