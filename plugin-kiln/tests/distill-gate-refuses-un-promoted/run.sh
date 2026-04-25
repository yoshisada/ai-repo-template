#!/usr/bin/env bash
# Test: distill-gate-refuses-un-promoted
#
# Validates: FR-004 + FR-005 + SC-002.
# The distill-gate scripts (detect-un-promoted.sh + invoke-promote-handoff.sh)
# correctly classify 3 raw open issues as un-promoted and surface per-entry
# hand-off envelopes. The Skill.md layer handles the actual user decision
# loop — this fixture pins the script-contract surface that the Skill
# consumes.
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DETECT="$REPO_ROOT/plugin-kiln/scripts/distill/detect-un-promoted.sh"
HANDOFF="$REPO_ROOT/plugin-kiln/scripts/distill/invoke-promote-handoff.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"
mkdir -p .kiln/issues

# 3 open issues, no roadmap items citing them.
for slug in foo bar baz; do
  cat > ".kiln/issues/2026-04-24-$slug.md" <<EOF
---
id: 2026-04-24-$slug
title: "$slug needs attention"
status: open
---

# Body for $slug
EOF
done

# Classify.
CLASS=$(bash "$DETECT" .kiln/issues/*.md)
COUNT=$(printf '%s\n' "$CLASS" | wc -l | tr -d ' ')
[[ "$COUNT" == "3" ]] \
  || { echo "FAIL: expected 3 classification records, got $COUNT" >&2; echo "$CLASS" >&2; exit 1; }

# All 3 should be un-promoted.
UN_COUNT=$(printf '%s\n' "$CLASS" | jq -rs '[.[] | select(.status=="un-promoted")] | length')
[[ "$UN_COUNT" == "3" ]] \
  || { echo "FAIL: expected 3 un-promoted, got $UN_COUNT" >&2; exit 1; }

# Hand-off envelopes.
UN_PATHS=$(printf '%s\n' "$CLASS" | jq -r 'select(.status=="un-promoted") | .path')
HANDOFF_OUT=$(bash "$HANDOFF" $UN_PATHS)
ENVELOPE_COUNT=$(printf '%s\n' "$HANDOFF_OUT" | wc -l | tr -d ' ')
[[ "$ENVELOPE_COUNT" == "3" ]] \
  || { echo "FAIL: expected 3 hand-off envelopes, got $ENVELOPE_COUNT" >&2; exit 1; }

# Each envelope MUST carry path, title, prompt.
printf '%s\n' "$HANDOFF_OUT" | jq -e 'has("path") and has("title") and has("prompt")' >/dev/null \
  || { echo "FAIL: envelope schema missing required keys" >&2; echo "$HANDOFF_OUT" >&2; exit 1; }

# Prompt must include [accept|skip] marker so the Skill can parse per-entry.
printf '%s\n' "$HANDOFF_OUT" | grep -q "\[accept|skip\]" \
  || { echo "FAIL: envelope prompt missing [accept|skip] marker" >&2; exit 1; }

# Side-effect check — no new roadmap items, no PRD written.
[[ ! -d .kiln/roadmap ]] \
  || { echo "FAIL: gate wrote to .kiln/roadmap/ despite skip-all simulation" >&2; exit 1; }
[[ ! -d docs/features ]] \
  || { echo "FAIL: gate wrote a PRD despite skip-all simulation" >&2; exit 1; }

echo "PASS: distill-gate-refuses-un-promoted — 3 un-promoted, 3 envelopes, no PRD, no side effects"
