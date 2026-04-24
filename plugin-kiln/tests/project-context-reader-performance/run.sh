#!/usr/bin/env bash
# Test: project-context-reader-performance
#
# Validates: NFR-001 (<2 s on ~50 PRDs + ~100 roadmap items), SC-006.
#
# Acceptance scenario this validates:
#   "Reader completes in <2 s on a synthetic repo with 50 PRDs + 100 items."
#
# The fixture is synthesized on-the-fly in a tempdir so it doesn't bloat the
# tree; we then point the reader at it and measure wall-clock.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/../../scripts/context/read-project-context.sh"

if [[ ! -f "$READER" ]]; then
  echo "FAIL: reader script missing at $READER" >&2
  exit 1
fi

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT

# 50 PRDs
mkdir -p "$REPO/docs/features"
for i in $(seq -w 1 50); do
  d="$REPO/docs/features/2026-04-${i:0:2}-feature-${i}"
  mkdir -p "$d"
  cat > "$d/PRD.md" <<EOF
---
theme: t-$((10#$i % 5))
---

# Feature ${i}

Synthetic PRD body.
EOF
done

# 100 roadmap items
mkdir -p "$REPO/.kiln/roadmap/items"
for i in $(seq -w 1 100); do
  f="$REPO/.kiln/roadmap/items/2026-04-10-item-${i}.md"
  cat > "$f" <<EOF
---
id: 2026-04-10-item-${i}
title: "Item ${i}"
kind: feature
date: 2026-04-10
status: open
phase: current
state: in-phase
blast_radius: feature
review_cost: moderate
context_cost: 1 session
---

# Item ${i}
EOF
done

# 5 phases
mkdir -p "$REPO/.kiln/roadmap/phases"
for p in foundations current next later unsorted; do
  cat > "$REPO/.kiln/roadmap/phases/${p}.md" <<EOF
---
name: ${p}
status: planned
order: 0
started: null
completed: null
---

# ${p}

## Items
EOF
done

# Time the run.
START_NS="$(date +%s%N 2>/dev/null || date +%s000000000)"
if [[ "$START_NS" == *N* ]]; then
  # macOS `date` without %N support — fall back to seconds.
  START_S="$(date +%s)"
  bash "$READER" --repo-root "$REPO" > /dev/null
  END_S="$(date +%s)"
  ELAPSED_MS=$(( (END_S - START_S) * 1000 ))
else
  bash "$READER" --repo-root "$REPO" > /dev/null
  END_NS="$(date +%s%N 2>/dev/null || date +%s000000000)"
  ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
fi

echo "elapsed: ${ELAPSED_MS} ms (budget: 2000 ms)"

if [[ "$ELAPSED_MS" -gt 2000 ]]; then
  echo "FAIL: reader exceeded 2 s budget on 50-PRD + 100-item fixture (NFR-001)" >&2
  exit 1
fi

echo "PASS: reader ran in ${ELAPSED_MS}ms on synthetic 50+100 fixture"
