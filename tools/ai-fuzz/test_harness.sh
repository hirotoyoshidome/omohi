#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash -n "$SCRIPT_DIR/run_session.sh"
bash -n "$SCRIPT_DIR/container_runner.sh"
bash -n "$SCRIPT_DIR/examples/basic_session.sh"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omohi-ai-fuzz-test.XXXXXX")"
  trap 'rm -rf "$OUTPUT_DIR"' EXIT

  "$SCRIPT_DIR/run_session.sh" \
    --output-dir "$OUTPUT_DIR" \
    "$SCRIPT_DIR/examples/basic_session.sh"

  [ -f "$OUTPUT_DIR/session.json" ]
  [ -f "$OUTPUT_DIR/findings.json" ]
  [ -f "$OUTPUT_DIR/SUMMARY.md" ]
else
  echo "docker daemon not available; syntax checks only"
fi
