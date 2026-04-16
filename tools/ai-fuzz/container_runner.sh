#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <session-file> <output-dir>" >&2
  exit 2
fi

SESSION_FILE="$1"
OUTPUT_DIR="$2"
OMOHI_BIN="${OMOHI_BIN:-/usr/local/bin/omohi}"
HARNESS_ROOT="${HARNESS_ROOT:-/tmp/omohi-ai-fuzz}"
WORK_ROOT="${WORK_ROOT:-$HARNESS_ROOT/work}"
HOME_DIR="${HOME_DIR:-$HARNESS_ROOT/home}"
DEFAULT_STEP_TIMEOUT_SECONDS="${DEFAULT_STEP_TIMEOUT_SECONDS:-10}"

mkdir -p "$OUTPUT_DIR/steps" "$WORK_ROOT" "$HOME_DIR"
export HOME="$HOME_DIR"

SESSION_NAME="$(basename "$SESSION_FILE")"
STEP_TIMEOUT_SECONDS="$DEFAULT_STEP_TIMEOUT_SECONDS"
STEP_INDEX=0
FINDING_INDEX=0
LAST_EXIT_CODE=0
LAST_STDOUT=""
LAST_STDERR=""
LAST_STDOUT_FILE=""
LAST_STDERR_FILE=""
LAST_TIMED_OUT=0
LAST_COMMAND_DISPLAY=""
LAST_STEP_KIND=""

declare -a STEP_COMMANDS=()
declare -a STEP_EXIT_CODES=()

STEPS_NDJSON="$OUTPUT_DIR/.steps.ndjson"
FINDINGS_NDJSON="$OUTPUT_DIR/.findings.ndjson"
: > "$STEPS_NDJSON"
: > "$FINDINGS_NDJSON"

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

epoch_ms() {
  date -u +%s%3N
}

json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

join_json_array_from_bash_array() {
  local -n ref="$1"
  local result="["
  local i

  for ((i = 0; i < ${#ref[@]}; i += 1)); do
    if [ "$i" -gt 0 ]; then
      result+=", "
    fi
    result+="$(json_escape "${ref[$i]}")"
  done

  result+="]"
  printf '%s' "$result"
}

ndjson_to_array() {
  local file_path="$1"
  local first=1

  printf '['
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '%s' "$line"
    first=0
  done < "$file_path"
  printf ']'
}

ensure_safe_relative_path() {
  local path="$1"
  if [ -z "$path" ]; then
    echo "relative path must not be empty" >&2
    exit 2
  fi
  if [[ "$path" = /* ]]; then
    echo "absolute paths are not allowed in file helpers: $path" >&2
    exit 2
  fi
  if [[ "$path" == *".."* ]]; then
    echo "parent traversal is not allowed in file helpers: $path" >&2
    exit 2
  fi
}

work_path() {
  ensure_safe_relative_path "$1"
  printf '%s/%s\n' "$WORK_ROOT" "$1"
}

session_name() {
  SESSION_NAME="$1"
}

set_step_timeout() {
  STEP_TIMEOUT_SECONDS="$1"
}

build_command_display() {
  local display="$1"
  shift
  local token

  for token in "$@"; do
    display+=" $(printf '%q' "$token")"
  done

  printf '%s\n' "$display"
}

is_expected_exit_code() {
  local expected_csv="$1"
  local actual="$2"
  local expected

  IFS=',' read -r -a expected <<< "$expected_csv"
  for expected in "${expected[@]}"; do
    if [ "$expected" = "$actual" ]; then
      return 0
    fi
  done
  return 1
}

append_finding() {
  local classification="$1"
  local severity="$2"
  local title="$3"
  local why_flagged="$4"
  local trigger_step="$5"
  local stdout_path="$6"
  local stderr_path="$7"
  FINDING_INDEX=$((FINDING_INDEX + 1))
  local id="finding-$(printf '%03d' "$FINDING_INDEX")"
  local i
  local reproduction=()

  for ((i = 0; i < trigger_step; i += 1)); do
    reproduction+=("${STEP_COMMANDS[$i]}")
  done

  printf '{' >> "$FINDINGS_NDJSON"
  printf '"id":%s,' "$(json_escape "$id")" >> "$FINDINGS_NDJSON"
  printf '"classification":%s,' "$(json_escape "$classification")" >> "$FINDINGS_NDJSON"
  printf '"severity":%s,' "$(json_escape "$severity")" >> "$FINDINGS_NDJSON"
  printf '"trigger_step":%s,' "$(json_escape "$(printf '%03d' "$trigger_step")")" >> "$FINDINGS_NDJSON"
  printf '"title":%s,' "$(json_escape "$title")" >> "$FINDINGS_NDJSON"
  printf '"why_flagged":%s,' "$(json_escape "$why_flagged")" >> "$FINDINGS_NDJSON"
  printf '"reproduction_steps":%s,' "$(join_json_array_from_bash_array reproduction)" >> "$FINDINGS_NDJSON"
  printf '"observed_exit_codes":[%s],' "${STEP_EXIT_CODES[$((trigger_step - 1))]}" >> "$FINDINGS_NDJSON"
  printf '"related_output_paths":{"stdout":%s,"stderr":%s}' \
    "$(json_escape "$stdout_path")" \
    "$(json_escape "$stderr_path")" >> "$FINDINGS_NDJSON"
  printf '}\n' >> "$FINDINGS_NDJSON"
}

scan_step_findings() {
  local expected_csv="$1"
  local actual="$2"
  local stdout_path="$3"
  local stderr_path="$4"

  if [ "$LAST_TIMED_OUT" -eq 1 ]; then
    append_finding "timeout" "high" "Step timed out" \
      "The step exceeded the configured timeout of ${STEP_TIMEOUT_SECONDS}s." \
      "$STEP_INDEX" "$stdout_path" "$stderr_path"
    return
  fi

  if ! is_expected_exit_code "$expected_csv" "$actual"; then
    append_finding "unexpected_exit_code" "medium" "Unexpected exit code" \
      "Expected exit code(s) ${expected_csv}, but observed ${actual}." \
      "$STEP_INDEX" "$stdout_path" "$stderr_path"
  fi

  if [ "$actual" -ge 128 ]; then
    append_finding "crash_signal" "high" "Process exited with signal-style status" \
      "The command returned ${actual}, which suggests an abnormal termination." \
      "$STEP_INDEX" "$stdout_path" "$stderr_path"
    return
  fi

  if [[ "$LAST_STDERR" == *"panic"* ]] || [[ "$LAST_STDERR" == *"segmentation fault"* ]] || [[ "$LAST_STDERR" == *"assertion failed"* ]]; then
    append_finding "runtime_error_marker" "high" "Runtime failure marker detected" \
      "stderr contains a panic, assertion, or segmentation marker." \
      "$STEP_INDEX" "$stdout_path" "$stderr_path"
  fi
}

run_logged_command() {
  local kind="$1"
  local expected_csv="$2"
  shift 2

  STEP_INDEX=$((STEP_INDEX + 1))
  local step_label
  step_label="$(printf '%03d' "$STEP_INDEX")"
  local stdout_path="steps/${step_label}-stdout.txt"
  local stderr_path="steps/${step_label}-stderr.txt"
  local stdout_file="$OUTPUT_DIR/$stdout_path"
  local stderr_file="$OUTPUT_DIR/$stderr_path"
  local started_at
  local finished_at
  local start_ms
  local end_ms
  local duration_ms

  started_at="$(now_utc)"
  start_ms="$(epoch_ms)"
  LAST_TIMED_OUT=0

  set +e
  if command -v timeout >/dev/null 2>&1; then
    (
      cd "$WORK_ROOT"
      timeout "${STEP_TIMEOUT_SECONDS}s" "$@"
    ) >"$stdout_file" 2>"$stderr_file"
  else
    (
      cd "$WORK_ROOT"
      "$@"
    ) >"$stdout_file" 2>"$stderr_file"
  fi
  LAST_EXIT_CODE=$?
  set -e

  if [ "$LAST_EXIT_CODE" -eq 124 ]; then
    LAST_TIMED_OUT=1
  fi

  finished_at="$(now_utc)"
  end_ms="$(epoch_ms)"
  duration_ms=$((end_ms - start_ms))
  LAST_STDOUT_FILE="$stdout_file"
  LAST_STDERR_FILE="$stderr_file"
  LAST_STDOUT="$(cat "$stdout_file")"
  LAST_STDERR="$(cat "$stderr_file")"
  LAST_STEP_KIND="$kind"

  STEP_COMMANDS+=("$LAST_COMMAND_DISPLAY")
  STEP_EXIT_CODES+=("$LAST_EXIT_CODE")

  printf '{' >> "$STEPS_NDJSON"
  printf '"index":%s,' "$(json_escape "$step_label")" >> "$STEPS_NDJSON"
  printf '"kind":%s,' "$(json_escape "$kind")" >> "$STEPS_NDJSON"
  printf '"command":%s,' "$(json_escape "$LAST_COMMAND_DISPLAY")" >> "$STEPS_NDJSON"
  printf '"expected_exit_codes":%s,' "$(json_escape "$expected_csv")" >> "$STEPS_NDJSON"
  printf '"started_at":%s,' "$(json_escape "$started_at")" >> "$STEPS_NDJSON"
  printf '"finished_at":%s,' "$(json_escape "$finished_at")" >> "$STEPS_NDJSON"
  printf '"duration_ms":%s,' "$duration_ms" >> "$STEPS_NDJSON"
  printf '"exit_code":%s,' "$LAST_EXIT_CODE" >> "$STEPS_NDJSON"
  printf '"timed_out":%s,' "$([ "$LAST_TIMED_OUT" -eq 1 ] && printf 'true' || printf 'false')" >> "$STEPS_NDJSON"
  printf '"stdout_path":%s,' "$(json_escape "$stdout_path")" >> "$STEPS_NDJSON"
  printf '"stderr_path":%s' "$(json_escape "$stderr_path")" >> "$STEPS_NDJSON"
  printf '}\n' >> "$STEPS_NDJSON"

  scan_step_findings "$expected_csv" "$LAST_EXIT_CODE" "$stdout_path" "$stderr_path"
}

record_note_step() {
  local kind="$1"
  local command_display="$2"

  STEP_INDEX=$((STEP_INDEX + 1))
  local step_label
  step_label="$(printf '%03d' "$STEP_INDEX")"
  local stdout_path="steps/${step_label}-stdout.txt"
  local stderr_path="steps/${step_label}-stderr.txt"
  local stdout_file="$OUTPUT_DIR/$stdout_path"
  local stderr_file="$OUTPUT_DIR/$stderr_path"
  local started_at

  started_at="$(now_utc)"
  : > "$stdout_file"
  : > "$stderr_file"

  LAST_COMMAND_DISPLAY="$command_display"
  LAST_STEP_KIND="$kind"
  LAST_EXIT_CODE=0
  LAST_TIMED_OUT=0
  LAST_STDOUT=""
  LAST_STDERR=""
  LAST_STDOUT_FILE="$stdout_file"
  LAST_STDERR_FILE="$stderr_file"

  STEP_COMMANDS+=("$LAST_COMMAND_DISPLAY")
  STEP_EXIT_CODES+=("$LAST_EXIT_CODE")

  printf '{' >> "$STEPS_NDJSON"
  printf '"index":%s,' "$(json_escape "$step_label")" >> "$STEPS_NDJSON"
  printf '"kind":%s,' "$(json_escape "$kind")" >> "$STEPS_NDJSON"
  printf '"command":%s,' "$(json_escape "$LAST_COMMAND_DISPLAY")" >> "$STEPS_NDJSON"
  printf '"expected_exit_codes":%s,' "$(json_escape "0")" >> "$STEPS_NDJSON"
  printf '"started_at":%s,' "$(json_escape "$started_at")" >> "$STEPS_NDJSON"
  printf '"finished_at":%s,' "$(json_escape "$started_at")" >> "$STEPS_NDJSON"
  printf '"duration_ms":0,' >> "$STEPS_NDJSON"
  printf '"exit_code":0,' >> "$STEPS_NDJSON"
  printf '"timed_out":false,' >> "$STEPS_NDJSON"
  printf '"stdout_path":%s,' "$(json_escape "$stdout_path")" >> "$STEPS_NDJSON"
  printf '"stderr_path":%s' "$(json_escape "$stderr_path")" >> "$STEPS_NDJSON"
  printf '}\n' >> "$STEPS_NDJSON"
}

omohi_exec() {
  LAST_COMMAND_DISPLAY="$(build_command_display "omohi" "$@")"
  run_logged_command "omohi.exec" "0" "$OMOHI_BIN" "$@"
}

omohi_exec_expect() {
  local expected_csv="$1"
  shift
  LAST_COMMAND_DISPLAY="$(build_command_display "omohi" "$@")"
  run_logged_command "omohi.exec" "$expected_csv" "$OMOHI_BIN" "$@"
}

shell_exec() {
  local shell_command="$1"
  LAST_COMMAND_DISPLAY="bash -lc $(printf '%q' "$shell_command")"
  run_logged_command "shell.exec" "0" bash -lc "$shell_command"
}

shell_exec_expect() {
  local expected_csv="$1"
  local shell_command="$2"
  LAST_COMMAND_DISPLAY="bash -lc $(printf '%q' "$shell_command")"
  run_logged_command "shell.exec" "$expected_csv" bash -lc "$shell_command"
}

file_write() {
  local path
  path="$(work_path "$1")"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$2" > "$path"
  record_note_step "file.write" "$(build_command_display "file.write" "$1")"
}

file_append() {
  local path
  path="$(work_path "$1")"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$2" >> "$path"
  record_note_step "file.append" "$(build_command_display "file.append" "$1")"
}

file_delete() {
  local path
  path="$(work_path "$1")"
  rm -rf "$path"
  record_note_step "file.delete" "$(build_command_display "file.delete" "$1")"
}

file_mkdir() {
  local path
  path="$(work_path "$1")"
  mkdir -p "$path"
  record_note_step "file.mkdir" "$(build_command_display "file.mkdir" "$1")"
}

file_move() {
  local src
  local dst
  src="$(work_path "$1")"
  dst="$(work_path "$2")"
  mkdir -p "$(dirname "$dst")"
  mv "$src" "$dst"
  record_note_step "file.move" "$(build_command_display "file.move" "$1" "$2")"
}

capture_commit_id() {
  local var_name="$1"
  if [[ "$LAST_STDOUT" =~ Committed[[:space:]]+([0-9a-f]{64}) ]]; then
    printf -v "$var_name" '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  echo "unable to capture commit id from the previous stdout" >&2
  return 1
}

write_session_json() {
  local version_output
  local target_version

  if version_output="$("$OMOHI_BIN" version 2>/dev/null)"; then
    target_version="$version_output"
  else
    target_version="unknown"
  fi

  printf '{\n' > "$OUTPUT_DIR/session.json"
  printf '  "session_name": %s,\n' "$(json_escape "$SESSION_NAME")" >> "$OUTPUT_DIR/session.json"
  printf '  "session_file": %s,\n' "$(json_escape "$(basename "$SESSION_FILE")")" >> "$OUTPUT_DIR/session.json"
  printf '  "started_at": %s,\n' "$(json_escape "$SESSION_STARTED_AT")" >> "$OUTPUT_DIR/session.json"
  printf '  "finished_at": %s,\n' "$(json_escape "$SESSION_FINISHED_AT")" >> "$OUTPUT_DIR/session.json"
  printf '  "step_timeout_seconds": %s,\n' "$STEP_TIMEOUT_SECONDS" >> "$OUTPUT_DIR/session.json"
  printf '  "omohi_version": %s,\n' "$(json_escape "$target_version")" >> "$OUTPUT_DIR/session.json"
  printf '  "work_root": %s,\n' "$(json_escape "$WORK_ROOT")" >> "$OUTPUT_DIR/session.json"
  printf '  "home_dir": %s,\n' "$(json_escape "$HOME_DIR")" >> "$OUTPUT_DIR/session.json"
  printf '  "step_count": %s,\n' "$STEP_INDEX" >> "$OUTPUT_DIR/session.json"
  printf '  "steps": %s\n' "$(ndjson_to_array "$STEPS_NDJSON")" >> "$OUTPUT_DIR/session.json"
  printf '}\n' >> "$OUTPUT_DIR/session.json"
}

write_findings_json() {
  printf '%s\n' "$(ndjson_to_array "$FINDINGS_NDJSON")" > "$OUTPUT_DIR/findings.json"
}

write_summary() {
  local findings_count
  findings_count="$(wc -l < "$FINDINGS_NDJSON" | tr -d ' ')"
  {
    printf '# AI Fuzz Session Summary\n\n'
    printf -- '- Session: `%s`\n' "$SESSION_NAME"
    printf -- '- Started: `%s`\n' "$SESSION_STARTED_AT"
    printf -- '- Finished: `%s`\n' "$SESSION_FINISHED_AT"
    printf -- '- Steps: `%s`\n' "$STEP_INDEX"
    printf -- '- Findings: `%s`\n' "$findings_count"
    printf -- '- Session JSON: `session.json`\n'
    printf -- '- Findings JSON: `findings.json`\n\n'

    if [ "$findings_count" -eq 0 ]; then
      printf 'No findings were flagged by the v1 heuristics.\n'
      return
    fi

    printf '## Findings\n\n'
    awk '
      BEGIN {
        FS="\""
      }
      {
        id=""
        classification=""
        severity=""
        title=""
        trigger=""
        why=""
        stdout=""
        stderr=""
        for (i = 2; i <= NF; i += 2) {
          if ($(i) == "id") id = $(i + 2)
          if ($(i) == "classification") classification = $(i + 2)
          if ($(i) == "severity") severity = $(i + 2)
          if ($(i) == "title") title = $(i + 2)
          if ($(i) == "trigger_step") trigger = $(i + 2)
          if ($(i) == "why_flagged") why = $(i + 2)
          if ($(i) == "stdout") stdout = $(i + 2)
          if ($(i) == "stderr") stderr = $(i + 2)
        }
        printf "### %s\n\n", title
        printf -- "- ID: `%s`\n", id
        printf -- "- Severity: `%s`\n", severity
        printf -- "- Classification: `%s`\n", classification
        printf -- "- Trigger Step: `%s`\n", trigger
        printf -- "- Why: %s\n", why
        printf -- "- stdout: `%s`\n", stdout
        printf -- "- stderr: `%s`\n\n", stderr
      }
    ' "$FINDINGS_NDJSON"
  } > "$OUTPUT_DIR/SUMMARY.md"
}

SESSION_STARTED_AT="$(now_utc)"
source "$SESSION_FILE"
SESSION_FINISHED_AT="$(now_utc)"

write_session_json
write_findings_json
write_summary

rm -f "$STEPS_NDJSON" "$FINDINGS_NDJSON"
