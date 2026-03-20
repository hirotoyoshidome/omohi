#!/usr/bin/env bash
set -euo pipefail

PREFIX="${HOME}/.local"
OPTIMIZE="ReleaseSafe"
RUN_TESTS=1

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Build and install omohi from source.

Options:
  --prefix <dir>      Install prefix (default: $HOME/.local)
  --optimize <mode>   Zig optimize mode (default: ReleaseSafe)
  --skip-tests        Skip running tests before build
  --help              Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      if [[ $# -lt 2 ]]; then
        echo "error: --prefix requires a value" >&2
        usage
        exit 2
      fi
      PREFIX="$2"
      shift 2
      ;;
    --optimize)
      if [[ $# -lt 2 ]]; then
        echo "error: --optimize requires a value" >&2
        usage
        exit 2
      fi
      OPTIMIZE="$2"
      shift 2
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! command -v zig >/dev/null 2>&1; then
  echo "error: zig is not installed or not in PATH" >&2
  exit 1
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  echo "Running tests..."
  zig build test --summary all
fi

echo "Building omohi (optimize=${OPTIMIZE})..."
zig build -Doptimize="${OPTIMIZE}"

bindir="${PREFIX}/bin"
dst="${bindir}/omohi"

mkdir -p "${bindir}"
cp -f zig-out/bin/omohi "${dst}"
chmod 755 "${dst}"

echo "Installed: ${dst}"

case ":${PATH}:" in
  *":${bindir}:"*)
    ;;
  *)
    echo "Note: ${bindir} is not in PATH. Add this to your shell profile:"
    echo "  export PATH=\"${bindir}:\$PATH\""
    ;;
esac
