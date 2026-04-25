#!/usr/bin/env bash
# build-all.sh — walk plugin-kiln/agents/_src/*.md, run resolve.sh on each,
# write compiled output to plugin-kiln/agents/<role>.md.
#
# Idempotent. Exit non-zero if resolver fails on any file.
# Owner: impl-include-preprocessor track (Theme B, FR-B-1 hybrid build step).
#
# Usage:
#   plugin-kiln/scripts/agent-includes/build-all.sh
#   plugin-kiln/scripts/agent-includes/build-all.sh --out-dir <dir>   # write to alt dir (used by check-compiled.sh)
#
# Sources: plugin-kiln/agents/_src/*.md
# Default output: plugin-kiln/agents/<role>.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_KILN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESOLVER="$SCRIPT_DIR/resolve.sh"
SRC_DIR="$PLUGIN_KILN_DIR/agents/_src"
OUT_DIR="$PLUGIN_KILN_DIR/agents"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "build-all.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$SRC_DIR" ]]; then
  # No sources to compile — exit 0 (no-op).
  exit 0
fi

mkdir -p "$OUT_DIR"

shopt -s nullglob
sources=( "$SRC_DIR"/*.md )
shopt -u nullglob

if [[ ${#sources[@]} -eq 0 ]]; then
  exit 0
fi

count=0
for src in "${sources[@]}"; do
  name="$(basename "$src")"
  out="$OUT_DIR/$name"
  if ! "$RESOLVER" "$src" > "$out.tmp"; then
    rm -f "$out.tmp"
    echo "build-all.sh: resolver failed on $src" >&2
    exit 1
  fi
  mv "$out.tmp" "$out"
  count=$((count + 1))
done

echo "build-all.sh: compiled $count source(s) → $OUT_DIR"
