#!/usr/bin/env bash
# Test: distill-gate-accepts-promoted
#
# Validates: FR-005 Acceptance Scenarios 2 + 4.
# Mixed bundle — 1 properly promoted source + 2 raw open issues. Gate
# classifies correctly (1 promoted, 2 un-promoted) and hand-off envelopes
# are emitted only for the un-promoted set.
#
# The reciprocal back-reference check (source.roadmap_item → item.promoted_from
# must match) is exercised by seeding a promoted source + its corresponding
# roadmap item.
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DETECT="$REPO_ROOT/plugin-kiln/scripts/distill/detect-un-promoted.sh"
HANDOFF="$REPO_ROOT/plugin-kiln/scripts/distill/invoke-promote-handoff.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"
mkdir -p .kiln/issues .kiln/roadmap/items

# Properly promoted issue + matching roadmap item (reciprocal back-reference).
cat > .kiln/issues/2026-04-24-promoted.md <<'EOF'
---
id: 2026-04-24-promoted
title: "Already promoted"
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-promoted.md
---

# Body
EOF
cat > .kiln/roadmap/items/2026-04-24-promoted.md <<'EOF'
---
id: 2026-04-24-promoted
title: "Already promoted"
kind: feature
date: 2026-04-24
status: open
phase: workflow-governance
state: planned
blast_radius: feature
review_cost: moderate
context_cost: "low"
promoted_from: .kiln/issues/2026-04-24-promoted.md
---

# Already promoted
EOF

# Two raw un-promoted issues.
for slug in raw1 raw2; do
  cat > ".kiln/issues/2026-04-24-$slug.md" <<EOF
---
id: 2026-04-24-$slug
title: "$slug needs attention"
status: open
---

# Body
EOF
done

CLASS=$(bash "$DETECT" .kiln/issues/*.md)

PROMOTED_COUNT=$(printf '%s\n' "$CLASS" | jq -rs '[.[] | select(.status=="promoted")] | length')
UN_COUNT=$(printf '%s\n' "$CLASS" | jq -rs '[.[] | select(.status=="un-promoted")] | length')

[[ "$PROMOTED_COUNT" == "1" ]] \
  || { echo "FAIL: expected 1 promoted, got $PROMOTED_COUNT" >&2; echo "$CLASS" >&2; exit 1; }
[[ "$UN_COUNT" == "2" ]] \
  || { echo "FAIL: expected 2 un-promoted, got $UN_COUNT" >&2; echo "$CLASS" >&2; exit 1; }

# Promoted record must carry roadmap_item path.
RI=$(printf '%s\n' "$CLASS" | jq -r 'select(.status=="promoted") | .roadmap_item')
[[ "$RI" == ".kiln/roadmap/items/2026-04-24-promoted.md" ]] \
  || { echo "FAIL: promoted record roadmap_item mismatch: $RI" >&2; exit 1; }

# Only un-promoted entries get hand-off envelopes.
UN_PATHS=$(printf '%s\n' "$CLASS" | jq -r 'select(.status=="un-promoted") | .path')
ENV_COUNT=$(bash "$HANDOFF" $UN_PATHS | wc -l | tr -d ' ')
[[ "$ENV_COUNT" == "2" ]] \
  || { echo "FAIL: expected 2 hand-off envelopes, got $ENV_COUNT" >&2; exit 1; }

echo "PASS: distill-gate-accepts-promoted — 1 promoted (reciprocal verified), 2 un-promoted, correct envelope count"
