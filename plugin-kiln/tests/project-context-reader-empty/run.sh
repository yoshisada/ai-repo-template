#!/usr/bin/env bash
# Test: project-context-reader-empty
#
# Validates: FR-002 (missing-source defensiveness — empty fields, not crash).
#
# Acceptance scenario this validates:
#   "Running the reader on a fully empty repo returns [] / null for all
#    collections, exit 0, no crash."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixture"
READER="$SCRIPT_DIR/../../scripts/context/read-project-context.sh"

if [[ ! -f "$READER" ]]; then
  echo "FAIL: reader script missing at $READER" >&2
  exit 1
fi

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

if ! bash "$READER" --repo-root "$FIXTURE" > "$OUT"; then
  echo "FAIL: reader crashed on empty fixture (FR-002)" >&2
  exit 1
fi

# prds, roadmap_items, roadmap_phases, plugins MUST be empty arrays.
for field in prds roadmap_items roadmap_phases plugins; do
  LEN="$(jq ".$field | length" "$OUT")"
  if [[ "$LEN" -ne 0 ]]; then
    echo "FAIL: expected .$field to be empty array on empty fixture; length=$LEN" >&2
    exit 1
  fi
done

# vision, claude_md, readme MUST be null (FR-002: NEVER emit empty string).
for field in vision claude_md readme; do
  KIND="$(jq -r ".$field | type" "$OUT")"
  if [[ "$KIND" != "null" ]]; then
    echo "FAIL: expected .$field to be null on empty fixture; got type=$KIND" >&2
    exit 1
  fi
done

echo "PASS: reader handles empty fixture per FR-002"
