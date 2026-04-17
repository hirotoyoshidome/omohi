#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tools/ai-fuzz/run_session.sh [options] <session-file>

Build the Docker image and run one AI fuzz session inside an isolated container.

Options:
  --image <name>        Docker image tag (default: omohi-ai-fuzz:local)
  --output-dir <dir>    Host directory for session artifacts
  --skip-build          Reuse the existing image and skip docker build
  --help                Show this help
USAGE
}

IMAGE_TAG="omohi-ai-fuzz:local"
OUTPUT_DIR=""
SKIP_BUILD=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is not installed or not in PATH" >&2
  exit 1
fi

SESSION_FILE="$1"
if [ ! -f "$SESSION_FILE" ]; then
  echo "error: session file not found: $SESSION_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SESSION_FILE_ABS="$(cd "$(dirname "$SESSION_FILE")" && pwd)/$(basename "$SESSION_FILE")"

if [ -z "$OUTPUT_DIR" ]; then
  session_base="$(basename "$SESSION_FILE" .sh)"
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  OUTPUT_DIR="$REPO_ROOT/.artifacts/ai-fuzz/${timestamp}-${session_base}"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
cp "$SESSION_FILE_ABS" "$OUTPUT_DIR/session.sh"

if [ "$SKIP_BUILD" -eq 0 ]; then
  docker build \
    --tag "$IMAGE_TAG" \
    --file "$REPO_ROOT/tools/ai-fuzz/Dockerfile" \
    "$REPO_ROOT"
fi

docker run --rm \
  --network none \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 256 \
  --memory 512m \
  --cpus 1.0 \
  --mount "type=bind,src=$OUTPUT_DIR,dst=/out" \
  --mount "type=bind,src=$SESSION_FILE_ABS,dst=/session/session.sh,readonly" \
  "$IMAGE_TAG" \
  /session/session.sh \
  /out

printf 'session artifacts: %s\n' "$OUTPUT_DIR"
printf 'summary: %s/SUMMARY.md\n' "$OUTPUT_DIR"
