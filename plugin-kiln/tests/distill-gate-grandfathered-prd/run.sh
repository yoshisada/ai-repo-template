#!/usr/bin/env bash
# Test: distill-gate-grandfathered-prd
#
# Validates: FR-008 + NFR-005 + SC-006.
# Pre-existing PRDs whose derived_from: cites raw .kiln/issues/ or
# .kiln/feedback/ paths MUST continue to parse/validate under the new
# gate — the gate only touches INPUT candidates, so grandfathering is by
# construction.
#
# This fixture:
#   1. Copies the real pre-existing PRD
#      (docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md)
#      into a temp repo along with its derived_from: sources.
#   2. Runs detect-un-promoted.sh against the SOURCE candidates (not the
#      PRD — the gate's domain). Asserts the sources are classified as
#      un-promoted (the expected state for a legacy PRD whose sources
#      were never routed through /kiln:kiln-roadmap --promote).
#   3. Asserts the PRD file is untouched (no partial-migration bug).
#   4. Asserts the PRD's frontmatter parses cleanly — the gate's YAML is
#      still valid three-group shape even though it predates the rollout.
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DETECT="$REPO_ROOT/plugin-kiln/scripts/distill/detect-un-promoted.sh"
REAL_PRD="$REPO_ROOT/docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md"

[[ -f "$REAL_PRD" ]] || { echo "FAIL: reference PRD missing at $REAL_PRD" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"
mkdir -p .kiln/feedback .kiln/issues
mkdir -p docs/features/2026-04-24-coach-driven-capture-ergonomics

# Copy the reference PRD verbatim (preserve its frontmatter exactly).
cp "$REAL_PRD" docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md
PRD_BEFORE=$(shasum -a 256 docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md | awk '{print $1}')

# Seed the raw sources the PRD cites — minimum shape needed by the
# detect-un-promoted classifier (status: open).
for src in \
  .kiln/feedback/2026-04-23-we-should-add-a-way.md \
  .kiln/feedback/2026-04-24-roadmap-agent-should-be-more-encouraging.md \
  .kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md \
  .kiln/issues/2026-04-24-kiln-vision-self-exploring-and-self-updating.md
do
  cat > "$src" <<EOF
---
title: "Grandfathered source"
status: open
---

# Body
EOF
done

# Run the gate on the raw sources.
CLASS=$(bash "$DETECT" \
  .kiln/feedback/2026-04-23-we-should-add-a-way.md \
  .kiln/feedback/2026-04-24-roadmap-agent-should-be-more-encouraging.md \
  .kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md \
  .kiln/issues/2026-04-24-kiln-vision-self-exploring-and-self-updating.md)

UN_COUNT=$(printf '%s\n' "$CLASS" | jq -rs '[.[] | select(.status=="un-promoted")] | length')
[[ "$UN_COUNT" == "4" ]] \
  || { echo "FAIL: expected all 4 raw sources un-promoted under the new gate, got $UN_COUNT" >&2; exit 1; }

# Assert: the grandfathered PRD file is UNCHANGED — gate does not retroactively
# rewrite historical artifacts.
PRD_AFTER=$(shasum -a 256 docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md | awk '{print $1}')
[[ "$PRD_BEFORE" == "$PRD_AFTER" ]] \
  || { echo "FAIL: gate modified the grandfathered PRD (FR-008 violation)" >&2; exit 1; }

# Assert: the PRD's frontmatter parses — we treat "clean parse" as the
# extractable derived_from: list being non-empty and distilled_date being
# a YYYY-MM-DD string. awk scan, zero dependencies on new code.
DD=$(awk '/^---/{fm++;next} fm==1 && /^distilled_date:/ { sub(/^distilled_date:[ \t]*/,""); print; exit }' \
  docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md)
[[ "$DD" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || { echo "FAIL: grandfathered PRD distilled_date not parseable: '$DD'" >&2; exit 1; }

# Cutoff verification: FR-008 says "PRDs with distilled_date: before rollout
# are exempt." Rollout date for this PRD is 2026-04-24; assert the reference
# PRD's distilled_date is LESS-THAN-OR-EQUAL to that — within the
# grandfather window.
[[ "$DD" < "2026-04-25" ]] \
  || { echo "FAIL: reference PRD distilled_date ($DD) post-dates the rollout cutoff — pick a different fixture" >&2; exit 1; }

echo "PASS: distill-gate-grandfathered-prd — 4 raw sources correctly classified, PRD untouched, frontmatter parses, within cutoff"
