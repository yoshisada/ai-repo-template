#!/usr/bin/env bash
# US4 — cross-surface routing confirm-never-silent; hand-off via Skill tool.
# FR-014b / PRD FR-014b: MUST invoke target skill.
# FR-036 / spec FR-036: test asserts invocation via side effect — an issue file
# appears under .kiln/issues/ and no roadmap item with non-seed content was written.
set -euo pipefail

ITEMS_DIR=".kiln/roadmap/items"
ISSUES_DIR=".kiln/issues"

# Filter out seed critiques from items dir
shopt -s nullglob
non_seed_items=0
for f in "$ITEMS_DIR"/*.md; do
  b=$(basename "$f" .md)
  case "$b" in
    *-too-many-tokens|*-unauditable-buggy-code|*-too-much-setup) continue ;;
    *) non_seed_items=$((non_seed_items + 1)) ;;
  esac
done

if [ "$non_seed_items" -ne 0 ]; then
  echo "FAIL: $non_seed_items non-seed roadmap item(s) were written when user routed to issue (b)" >&2
  echo "Expected 0 — the skill should have invoked kiln-report-issue instead." >&2
  ls "$ITEMS_DIR" >&2
  exit 1
fi

# An issue file should have been created as a side effect of the Skill invocation
if [ ! -d "$ISSUES_DIR" ]; then
  echo "FAIL: .kiln/issues/ does not exist — /kiln:kiln-report-issue was never invoked (FR-014b, FR-036)" >&2
  exit 1
fi

issue_count=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$issue_count" -lt 1 ]; then
  echo "FAIL: no issue file created — hand-off to /kiln:kiln-report-issue did not execute (FR-014b, FR-036)" >&2
  ls "$ISSUES_DIR" >&2 || true
  exit 1
fi

echo "PASS: cross-surface (b) routed to /kiln:kiln-report-issue, no roadmap item written" >&2
exit 0
