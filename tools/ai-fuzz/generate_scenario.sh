#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCENARIO_DIR="$SCRIPT_DIR/scenarios"
AI_PROVIDER="${AI:-auto}"
REQUESTED_NAME="${NAME:-}"
REQUEST_PROMPT="${PROMPT:-}"
FORCE_WRITE="${FORCE:-0}"
TEST_TAXONOMY_PATH="$REPO_ROOT/docs/test-taxonomy.md"

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

append_file_block() {
  local title="$1"
  local path="$2"
  local output_file="$3"

  if [ -f "$path" ]; then
    {
      printf '\n=== %s ===\n' "$title"
      cat "$path"
      printf '\n'
    } >>"$output_file"
  fi
}

append_grep_matches() {
  local title="$1"
  local pattern="$2"
  local path="$3"
  local output_file="$4"

  if [ -f "$path" ]; then
    {
      printf '\n=== %s ===\n' "$title"
      if ! rg -n "$pattern" "$path"; then
        printf '(no matches)\n'
      fi
      printf '\n'
    } >>"$output_file"
  fi
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
    request_instruction="Act as a beginner bug hunter. Inspect the current implementation context below, including docs and relevant source files, choose one useful bug-finding angle that does not just duplicate the smoke scenario, and build a scenario around that angle."
  fi

  cat >"$prompt_file" <<EOF
You are generating one AI fuzz scenario for the omohi repository.
Your role is: beginner bug hunter.

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
- Produce a realistic, reproducible scenario that fits the current omohi CLI behavior and current implementation.
- Read both documentation and relevant source files when choosing the scenario.
- Do not repeat the exact smoke scenario flow if a different useful angle is available.
- Keep the scenario focused and compact.
- Prefer bug-finding over happy-path regression.
- Target bugs that are plausible under ordinary or slightly-abusive real usage, roughly the kind of issue that maybe 1 out of 30 users could hit.
- Avoid ultra-niche or purely synthetic corner cases.
- You may use compact durability-style loops, repeated commands, boundary-value inputs, and lightweight randomized orderings if they remain reproducible and easy to inspect from artifacts.
- Strong candidate themes include:
  - boundary values and near-limit inputs
  - missing files and state transitions
  - repeated commands and idempotency surprises
  - order-sensitive workflows
  - cross-command interactions such as commit + tag + find + show
  - compact durability or repetition checks inside the harness

Implementation guidance:
- You are allowed and encouraged to inspect relevant files under docs/ and src/ before deciding.
- Pay special attention to docs/cli.md and command/store files under src/app/cli/command/, src/ops/, and src/store/api.zig.
- Favor scenarios that explore behaviors not already well covered by fixed smoke-style tests.

Naming instruction:
$name_instruction

Scenario request:
$request_instruction

Repository context:

=== AGENTS.md ===
$(cat "$REPO_ROOT/AGENTS.md")

=== docs/test-taxonomy.md ===
$(cat "$TEST_TAXONOMY_PATH")

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
EOF

  append_file_block "docs/cli.md" "$REPO_ROOT/docs/cli.md" "$prompt_file"
  append_grep_matches "src/app/cli/command/commit.zig relevant lines" "dry_run|missing|status|tag|empty|commit" "$REPO_ROOT/src/app/cli/command/commit.zig" "$prompt_file"
  append_grep_matches "src/app/cli/command/add.zig relevant lines" "MissingTrackedFile|missing|untrack --missing|add" "$REPO_ROOT/src/app/cli/command/add.zig" "$prompt_file"
  append_grep_matches "src/app/cli/command/find.zig relevant lines" "limit|empty|tag|find" "$REPO_ROOT/src/app/cli/command/find.zig" "$prompt_file"
  append_grep_matches "src/app/cli/command/tag_add.zig relevant lines" "tag|commit" "$REPO_ROOT/src/app/cli/command/tag_add.zig" "$prompt_file"
  append_grep_matches "src/app/cli/command/tag_rm.zig relevant lines" "tag|commit" "$REPO_ROOT/src/app/cli/command/tag_rm.zig" "$prompt_file"
  append_grep_matches "src/app/cli/command/tag_ls.zig relevant lines" "tag|commit" "$REPO_ROOT/src/app/cli/command/tag_ls.zig" "$prompt_file"
  append_grep_matches "src/store/api.zig relevant lines" "missing|status|find|tag|empty_only|non_empty_only|limit|MissingTrackedFile" "$REPO_ROOT/src/store/api.zig" "$prompt_file"

  cat >>"$prompt_file" <<EOF
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
