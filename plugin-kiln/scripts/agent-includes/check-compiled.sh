#!/usr/bin/env bash
# check-compiled.sh — CI gate (FR-B-7). Re-runs build-all.sh into a temp dir
# and asserts compiled-on-disk == build(sources). Stderr names drifted files.
#
# Owner: impl-include-preprocessor track (Theme B, FR-B-7 / SC-2).
#
# Usage:
#   plugin-kiln/scripts/agent-includes/check-compiled.sh
#
# Exit 0  — every committed agents/<role>.md matches build(_src/<role>.md)
# Exit 1  — drift detected (or build failure); stderr names the offending file(s)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_KILN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$PLUGIN_KILN_DIR/agents/_src"
COMMITTED_DIR="$PLUGIN_KILN_DIR/agents"
BUILD_SH="$SCRIPT_DIR/build-all.sh"

if [[ ! -d "$SRC_DIR" ]]; then
  # No sources → vacuously OK.
  exit 0
fi

TMP_OUT=$(mktemp -d)
trap 'rm -rf "$TMP_OUT"' EXIT

if ! "$BUILD_SH" --out-dir "$TMP_OUT" >/dev/null; then
  echo "check-compiled.sh: build-all.sh failed" >&2
  exit 1
fi

drift=0
shopt -s nullglob
for built in "$TMP_OUT"/*.md; do
  name="$(basename "$built")"
  committed="$COMMITTED_DIR/$name"
  if [[ ! -f "$committed" ]]; then
    echo "check-compiled.sh: drift — committed file missing: agents/$name" >&2
    drift=$((drift + 1))
    continue
  fi
  if ! diff -q "$built" "$committed" >/dev/null 2>&1; then
    echo "check-compiled.sh: drift — agents/$name differs from build(_src/$name)" >&2
    drift=$((drift + 1))
  fi
done
shopt -u nullglob

if [[ $drift -gt 0 ]]; then
  echo "check-compiled.sh: $drift file(s) drifted — run plugin-kiln/scripts/agent-includes/build-all.sh and commit" >&2
  exit 1
fi

echo "check-compiled.sh: OK — every _src/ file matches its compiled output"
exit 0
