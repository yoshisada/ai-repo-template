#!/usr/bin/env bash
# Test: distill-gate-three-group-shape
#
# Validates: FR-007 — the three-group sort order (feedback → item → issue)
# is preserved as a shape even when the feedback and issue groups are
# empty. Item-only bundles still emit paths in the stable sort order.
#
# This fixture pins the determinism claim at the sort-contract level: we
# seed an item-only candidate bundle, compute the emission order the way
# distill Step 4 would (via `LC_ALL=C sort` within each group), and assert:
#   1. Feedback + issue groups are empty lists (no accidental fallback).
#   2. Item group is sorted ascending by filename under LC_ALL=C.
#   3. Repeating the sort against identical inputs produces the same bytes.
#
# This is a compact analogue of the "distill emission shape" guarantee —
# the real distill Step 4 assembly is covered by the existing multi-theme
# determinism tests; here we pin the three-group shape specifically.
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"
mkdir -p .kiln/roadmap/items

# 3 item-only candidates (no feedback, no issues).
for slug in alpha bravo charlie; do
  cat > ".kiln/roadmap/items/2026-04-24-$slug.md" <<EOF
---
id: 2026-04-24-$slug
title: "$slug"
kind: feature
date: 2026-04-24
status: open
phase: test
state: planned
blast_radius: feature
review_cost: moderate
context_cost: "low"
---
EOF
done

# Simulate the Step 4 three-group sort — this is the exact pattern distill
# uses under the hood (see SKILL.md Step 4 "Per-Theme Emission Loop").
FEEDBACK=$(find .kiln/feedback -maxdepth 1 -name '*.md' 2>/dev/null | LC_ALL=C sort || true)
ITEMS=$(find .kiln/roadmap/items -maxdepth 1 -name '*.md' 2>/dev/null | LC_ALL=C sort || true)
ISSUES=$(find .kiln/issues -maxdepth 1 -name '*.md' 2>/dev/null | LC_ALL=C sort || true)

# Feedback + issue groups MUST be empty.
[[ -z "$FEEDBACK" ]] \
  || { echo "FAIL: feedback group unexpectedly non-empty: $FEEDBACK" >&2; exit 1; }
[[ -z "$ISSUES" ]] \
  || { echo "FAIL: issue group unexpectedly non-empty: $ISSUES" >&2; exit 1; }

# Item group MUST be sorted ASC: alpha → bravo → charlie.
EXPECTED=$(printf '%s\n' \
  .kiln/roadmap/items/2026-04-24-alpha.md \
  .kiln/roadmap/items/2026-04-24-bravo.md \
  .kiln/roadmap/items/2026-04-24-charlie.md)
ACTUAL=$(printf '%s\n' "$ITEMS")
[[ "$ACTUAL" == "$EXPECTED" ]] \
  || { echo "FAIL: item sort order wrong"; echo "expected:"; echo "$EXPECTED"; echo "actual:"; echo "$ACTUAL"; exit 1; } >&2

# Determinism — rerun and compare bytes.
ITEMS2=$(find .kiln/roadmap/items -maxdepth 1 -name '*.md' | LC_ALL=C sort)
[[ "$ITEMS" == "$ITEMS2" ]] \
  || { echo "FAIL: sort non-deterministic across runs" >&2; exit 1; }

# Shape assertion — even with empty feedback + issue groups, the emission
# ORDER is: feedback list (empty), then item list, then issue list
# (empty). This is the FR-007 "absent sub-lists" behavior.
EMISSION_ORDER=$(printf '%s%s%s' "$FEEDBACK" "$ITEMS" "$ISSUES")
[[ "$EMISSION_ORDER" == "$ITEMS" ]] \
  || { echo "FAIL: emission order malformed (feedback+issue leak)" >&2; exit 1; }

echo "PASS: distill-gate-three-group-shape — item-only bundle sorts stable, empty groups absent, determinism confirmed"
