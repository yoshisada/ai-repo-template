#!/usr/bin/env bash
# Test: roadmap-promote-idempotency
#
# Validates: FR-006 Acceptance Scenario 5 — a second invocation against a
# source already marked status: promoted exits 5 with a clear message and
# makes no writes (no new item file, source untouched).
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROMOTE="$REPO_ROOT/plugin-kiln/scripts/roadmap/promote-source.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"
mkdir -p .kiln/issues

# Seed a source that's ALREADY been promoted.
cat > .kiln/issues/2026-04-24-already-promoted.md <<'EOF'
---
id: 2026-04-24-already-promoted
title: "Already promoted item"
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-already-promoted.md
---

# Body preserved from the original promotion run.
EOF

BEFORE_SRC_HASH=$(shasum -a 256 .kiln/issues/2026-04-24-already-promoted.md | awk '{print $1}')

set +e
STDERR=$(bash "$PROMOTE" \
  --source .kiln/issues/2026-04-24-already-promoted.md \
  --kind feature \
  --blast-radius feature \
  --review-cost moderate \
  --context-cost "low" \
  --phase workflow-governance \
  --slug already-promoted 2>&1 >/dev/null)
RC=$?
set -e

[[ "$RC" == "5" ]] \
  || { echo "FAIL: expected exit 5, got $RC. stderr: $STDERR" >&2; exit 1; }
echo "$STDERR" | grep -qi "already" \
  || { echo "FAIL: stderr missing 'already' marker: $STDERR" >&2; exit 1; }

AFTER_SRC_HASH=$(shasum -a 256 .kiln/issues/2026-04-24-already-promoted.md | awk '{print $1}')
[[ "$BEFORE_SRC_HASH" == "$AFTER_SRC_HASH" ]] \
  || { echo "FAIL: source file modified despite exit 5" >&2; exit 1; }

# And no new item file should have been created.
[[ ! -f .kiln/roadmap/items/2026-04-24-already-promoted.md ]] \
  || { echo "FAIL: stray item file written despite exit 5" >&2; exit 1; }

echo "PASS: roadmap-promote-idempotency — exit 5, no writes"
