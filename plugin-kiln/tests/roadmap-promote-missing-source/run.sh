#!/usr/bin/env bash
# Test: roadmap-promote-missing-source
#
# Validates: FR-006 Acceptance Scenario 6 — --promote on a source that
# doesn't exist exits 3 with a clear "source not found" error; no writes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROMOTE="$REPO_ROOT/plugin-kiln/scripts/roadmap/promote-source.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"

set +e
STDERR=$(bash "$PROMOTE" \
  --source .kiln/issues/does-not-exist.md \
  --kind feature \
  --blast-radius feature \
  --review-cost moderate \
  --context-cost "low" \
  --phase workflow-governance \
  --slug ghost 2>&1 >/dev/null)
RC=$?
set -e

[[ "$RC" == "3" ]] \
  || { echo "FAIL: expected exit 3, got $RC. stderr: $STDERR" >&2; exit 1; }
echo "$STDERR" | grep -qi "does not exist" \
  || { echo "FAIL: stderr missing 'does not exist' marker: $STDERR" >&2; exit 1; }

[[ ! -d .kiln/roadmap ]] \
  || { echo "FAIL: stray .kiln/roadmap/ created despite exit 3" >&2; exit 1; }

echo "PASS: roadmap-promote-missing-source — exit 3, no writes"
