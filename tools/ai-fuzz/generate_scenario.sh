#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCENARIO_DIR="$SCRIPT_DIR/scenarios"
AI_PROVIDER="${AI:-auto}"
REQUESTED_NAME="${NAME:-}"
REQUEST_PROMPT="${PROMPT:-}"
FORCE_WRITE="${FORCE:-0}"

usage() {
  cat <<'USAGE'
Usage: make ai-fuzz-generate [AI=auto|codex|claude] [NAME=<name>] [PROMPT='...'] [FORCE=1]

Generate one AI fuzz scenario under tools/ai-fuzz/scenarios/.

Examples:
  make ai-fuzz-generate
  make ai-fuzz-generate PROMPT='Exercise empty-commit behavior with tags'
  make ai-fuzz-generate NAME=tag_empty_commit PROMPT='Exercise empty-commit behavior with tags'
  make ai-fuzz-generate AI=claude FORCE=1 NAME=tag_empty_commit
USAGE
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

select_provider() {
  case "$AI_PROVIDER" in
    auto)
      if command_exists codex; then
        printf 'codex\n'
        return
      fi
      if command_exists claude; then
        printf 'claude\n'
        return
      fi
      ;;
    codex|claude)
      if command_exists "$AI_PROVIDER"; then
        printf '%s\n' "$AI_PROVIDER"
        return
      fi
      echo "error: requested AI provider is not installed: $AI_PROVIDER" >&2
      exit 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unsupported AI provider: $AI_PROVIDER" >&2
      usage >&2
      exit 2
      ;;
  esac

  echo "error: neither codex nor claude is installed" >&2
  exit 1
}

slugify_name() {
  local raw="$1"
  local slug

  slug="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//; s/_+/_/g')"
  if [ -z "$slug" ]; then
    return 1
  fi
  printf '%s\n' "$slug"
}

extract_generated_name() {
  local response_file="$1"
  local generated_name

  generated_name="$(sed -n '1s/^SCENARIO_NAME:[[:space:]]*//p' "$response_file" | head -n 1)"
  if [ -z "$generated_name" ]; then
    echo "error: AI output did not include a SCENARIO_NAME header" >&2
    return 1
  fi

  slugify_name "$generated_name"
}

write_prompt() {
  local provider="$1"
  local prompt_file="$2"
  local name_instruction
  local request_instruction

  if [ -n "$REQUESTED_NAME" ]; then
    name_instruction="Use this exact scenario file basename: $REQUESTED_NAME"
  else
    name_instruction="Choose a concise scenario file basename yourself and return it in the required SCENARIO_NAME header."
  fi

  if [ -n "$REQUEST_PROMPT" ]; then
    request_instruction="Follow this requested theme strictly: $REQUEST_PROMPT"
  else
    request_instruction="Inspect the current implementation context below, choose one useful regression-finding angle that does not just duplicate the smoke scenario, and build a scenario around that angle."
  fi

  cat >"$prompt_file" <<EOF
You are generating one AI fuzz scenario for the omohi repository.

Return output in exactly this format:
SCENARIO_NAME: <snake_case_name>
#!/usr/bin/env bash
...

Hard requirements:
- Output only the scenario name header and the shell script body.
- Do not use Markdown fences.
- The script must start with #!/usr/bin/env bash.
- Use only the scenario DSL helpers documented below.
- Include session_name "<name>" and set_step_timeout <seconds>.
- Keep all file operations inside the container work root using file_* helpers and work_path.
- Use omohi_exec_expect or shell_exec_expect for intentional failures.
- Produce a realistic, reproducible scenario that fits the current omohi CLI behavior.
- Do not repeat the exact smoke scenario flow if a different useful angle is available.
- Keep the scenario focused and compact.

Naming instruction:
$name_instruction

Scenario request:
$request_instruction

Repository context:

=== AGENTS.md ===
$(cat "$REPO_ROOT/AGENTS.md")

=== tools/ai-fuzz/README.md ===
$(cat "$SCRIPT_DIR/README.md")

=== tools/ai-fuzz/scenarios/template.sh ===
$(cat "$SCENARIO_DIR/template.sh")

=== tools/ai-fuzz/scenarios/smoke_basic.sh ===
$(cat "$SCENARIO_DIR/smoke_basic.sh")

=== tools/ai-fuzz/run_session.sh ===
$(cat "$SCRIPT_DIR/run_session.sh")

=== tools/ai-fuzz/test_harness.sh ===
$(cat "$SCRIPT_DIR/test_harness.sh")

Provider hint:
- You are being called via $provider in non-interactive mode.
- Your answer will be written directly to a file after the SCENARIO_NAME header is parsed.
EOF
}

run_provider() {
  local provider="$1"
  local prompt_file="$2"
  local response_file="$3"
  local log_file="$4"

  case "$provider" in
    codex)
      codex exec \
        -C "$REPO_ROOT" \
        --skip-git-repo-check \
        --sandbox read-only \
        -o "$response_file" \
        - <"$prompt_file" >"$log_file" 2>&1
      ;;
    claude)
      claude \
        --print \
        --output-format text \
        --permission-mode default \
        --add-dir "$REPO_ROOT" \
        "$(cat "$prompt_file")" >"$response_file" 2>"$log_file"
      ;;
  esac
}

validate_script_body() {
  local script_file="$1"

  if ! grep -q '^#!/usr/bin/env bash$' "$script_file"; then
    echo "error: generated scenario does not start with #!/usr/bin/env bash" >&2
    return 1
  fi

  bash -n "$script_file"
}

PROVIDER="$(select_provider)"
mkdir -p "$SCENARIO_DIR"

if [ -n "$REQUESTED_NAME" ]; then
  SCENARIO_NAME="$(slugify_name "$REQUESTED_NAME")" || {
    echo "error: NAME could not be normalized into a valid scenario basename" >&2
    exit 1
  }
  SCENARIO_PATH="$SCENARIO_DIR/$SCENARIO_NAME.sh"
  if [ -e "$SCENARIO_PATH" ] && [ "$FORCE_WRITE" != "1" ]; then
    echo "error: scenario already exists: $SCENARIO_PATH" >&2
    echo "hint: rerun with FORCE=1 to overwrite it" >&2
    exit 1
  fi
fi

PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/omohi-ai-fuzz-prompt.XXXXXX")"
RESPONSE_FILE="$(mktemp "${TMPDIR:-/tmp}/omohi-ai-fuzz-response.XXXXXX")"
SCRIPT_BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/omohi-ai-fuzz-script.XXXXXX")"
PROVIDER_LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/omohi-ai-fuzz-provider.XXXXXX")"
trap 'rm -f "$PROMPT_FILE" "$RESPONSE_FILE" "$SCRIPT_BODY_FILE" "$PROVIDER_LOG_FILE"' EXIT

write_prompt "$PROVIDER" "$PROMPT_FILE"
if ! run_provider "$PROVIDER" "$PROMPT_FILE" "$RESPONSE_FILE" "$PROVIDER_LOG_FILE"; then
  if [ -s "$PROVIDER_LOG_FILE" ]; then
    cat "$PROVIDER_LOG_FILE" >&2
  fi
  exit 1
fi

if [ ! -s "$RESPONSE_FILE" ]; then
  if [ -s "$PROVIDER_LOG_FILE" ]; then
    cat "$PROVIDER_LOG_FILE" >&2
  fi
  echo "error: AI provider returned empty output" >&2
  exit 1
fi

if [ -z "${SCENARIO_NAME:-}" ]; then
  SCENARIO_NAME="$(extract_generated_name "$RESPONSE_FILE")" || exit 1
  SCENARIO_PATH="$SCENARIO_DIR/$SCENARIO_NAME.sh"
fi

if [ -e "$SCENARIO_PATH" ] && [ "$FORCE_WRITE" != "1" ]; then
  echo "error: scenario already exists: $SCENARIO_PATH" >&2
  echo "hint: rerun with FORCE=1 to overwrite it" >&2
  exit 1
fi

sed '1{/^SCENARIO_NAME:[[:space:]].*/d;}' "$RESPONSE_FILE" >"$SCRIPT_BODY_FILE"

if [ ! -s "$SCRIPT_BODY_FILE" ]; then
  echo "error: AI output did not include a shell script body" >&2
  exit 1
fi

cp "$SCRIPT_BODY_FILE" "$SCENARIO_PATH"
if ! validate_script_body "$SCENARIO_PATH"; then
  echo "error: generated scenario failed validation: $SCENARIO_PATH" >&2
  exit 1
fi

printf 'generated scenario: %s\n' "$SCENARIO_PATH"
printf 'provider: %s\n' "$PROVIDER"
if [ -n "$REQUEST_PROMPT" ]; then
  printf 'request: %s\n' "$REQUEST_PROMPT"
else
  printf 'request: auto-selected by AI from current implementation context\n'
fi
printf 'next: make ai-fuzz SCENARIO=%s\n' "tools/ai-fuzz/scenarios/$SCENARIO_NAME.sh"
