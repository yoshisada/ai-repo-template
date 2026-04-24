#!/usr/bin/env bash
# US10 — follow-up loop routes tactical next-input to /kiln:kiln-report-issue.
# FR-018c / FR-039 (graceful exit) / FR-014b / FR-036.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"
ISSUES_DIR=".kiln/issues"

# 1. One roadmap item should have been written from the first capture
shopt -s nullglob
roadmap_items=0
for f in "$ITEMS_DIR"/*.md; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
    *) roadmap_items=$((roadmap_items + 1)) ;;
  esac
done
if [ "$roadmap_items" -lt 1 ]; then
  echo "FAIL: expected ≥1 roadmap item from first capture, got $roadmap_items" >&2
  ls "$ITEMS_DIR" >&2 || true
  exit 1
fi

# 2. Follow-up (b) should have invoked /kiln:kiln-report-issue → .kiln/issues/<file>
if [ ! -d "$ISSUES_DIR" ]; then
  echo "FAIL: .kiln/issues/ does not exist — follow-up hand-off to /kiln:kiln-report-issue did not fire (FR-014b, FR-036)" >&2
  exit 1
fi
issue_count=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$issue_count" -lt 1 ]; then
  echo "FAIL: no issue file created — follow-up loop's hand-off did not execute (FR-018c + FR-014b)" >&2
  exit 1
fi

echo "PASS: follow-up loop routed second (tactical) input to kiln-report-issue" >&2
exit 0
