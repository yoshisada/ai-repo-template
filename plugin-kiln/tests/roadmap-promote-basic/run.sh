#!/usr/bin/env bash
# Test: roadmap-promote-basic
#
# Validates: FR-006 happy path + SC-003.
#   Run promote-source.sh against a seeded .kiln/issues/*.md with
#   status:open and a ≥200-char body. Assert:
#     1. New item file exists at .kiln/roadmap/items/<date>-<slug>.md.
#     2. New item frontmatter contains id, title, kind, date, status,
#        phase, state, blast_radius, review_cost, context_cost,
#        promoted_from: <source>.
#     3. Source frontmatter now has status: promoted + roadmap_item: <item>.
#     4. Source body bytes (after closing ---) are identical to pre-run.
#
# Note: this fixture drives promote-source.sh DIRECTLY — the SKILL.md
# --promote path is interview-driven and therefore covered at the skill
# integration level (manual smoke / pipeline test). The script contract
# is what this fixture pins.
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROMOTE="$REPO_ROOT/plugin-kiln/scripts/roadmap/promote-source.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

mkdir -p .kiln/issues
# Seed a source issue with ≥200 chars body and frontmatter.
cat > .kiln/issues/2026-04-24-widget-dark-mode.md <<'EOF'
---
id: 2026-04-24-widget-dark-mode
title: "Widget needs dark-mode support"
status: open
kind: issue
---

# Widget dark mode

The widget component currently hard-codes light-mode colors in its
render path. We need a dark-mode theme that matches the rest of the
UI. This should be straightforward — pull the palette tokens from the
design system and swap them in via CSS variables. No logic changes.

Outstanding questions: do we want a per-widget toggle, or follow the
global theme? Default to global.
EOF

# Snapshot the body bytes BEFORE promotion.
extract_body() {
  awk '/^---[[:space:]]*$/ { fm++; if (fm==2) { inbody=1; next } } inbody==1 { print }' "$1"
}
BEFORE_HASH=$(extract_body .kiln/issues/2026-04-24-widget-dark-mode.md | shasum -a 256 | awk '{print $1}')

# Invoke promote.
OUT=$(bash "$PROMOTE" \
  --source .kiln/issues/2026-04-24-widget-dark-mode.md \
  --kind feature \
  --blast-radius feature \
  --review-cost moderate \
  --context-cost "1-3 sessions" \
  --phase workflow-governance \
  --slug widget-dark-mode)

echo "script output: $OUT"

NEW_ITEM=$(printf '%s' "$OUT" | jq -r .new_item_path)
[[ -n "$NEW_ITEM" && -f "$NEW_ITEM" ]] \
  || { echo "FAIL: new item file not found at $NEW_ITEM" >&2; exit 1; }

# Assertion 1: new item has all required frontmatter fields.
REQUIRED=(id title kind date status phase state blast_radius review_cost context_cost promoted_from)
for k in "${REQUIRED[@]}"; do
  grep -qE "^${k}:" "$NEW_ITEM" \
    || { echo "FAIL: new item missing frontmatter key: $k" >&2; cat "$NEW_ITEM" >&2; exit 1; }
done

# Assertion 2: promoted_from matches supplied source path verbatim.
PF=$(awk '/^---/{fm++;next} fm==1 && /^promoted_from:/ { sub(/^promoted_from:[ \t]*/,""); print; exit }' "$NEW_ITEM")
[[ "$PF" == ".kiln/issues/2026-04-24-widget-dark-mode.md" ]] \
  || { echo "FAIL: promoted_from mismatch: $PF" >&2; exit 1; }

# Assertion 3: source flipped to status: promoted + roadmap_item:.
SRC=.kiln/issues/2026-04-24-widget-dark-mode.md
NEW_STATUS=$(awk '/^---/{fm++;next} fm==1 && /^status:/ { sub(/^status:[ \t]*/,""); print; exit }' "$SRC")
NEW_RI=$(awk '/^---/{fm++;next} fm==1 && /^roadmap_item:/ { sub(/^roadmap_item:[ \t]*/,""); print; exit }' "$SRC")
[[ "$NEW_STATUS" == "promoted" ]] \
  || { echo "FAIL: source status not 'promoted' (got: $NEW_STATUS)" >&2; exit 1; }
[[ "$NEW_RI" == "$NEW_ITEM" ]] \
  || { echo "FAIL: source roadmap_item mismatch: $NEW_RI vs $NEW_ITEM" >&2; exit 1; }

# Assertion 4: body bytes unchanged (NFR-003). Covered more rigorously
# in roadmap-promote-byte-preserve; asserting here too for belt-and-
# suspenders.
AFTER_HASH=$(extract_body "$SRC" | shasum -a 256 | awk '{print $1}')
[[ "$BEFORE_HASH" == "$AFTER_HASH" ]] \
  || { echo "FAIL: body bytes drifted after promote (NFR-003)" >&2; exit 1; }

echo "PASS: roadmap-promote-basic — new item written, source flipped, body byte-preserved"
