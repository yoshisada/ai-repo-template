#!/usr/bin/env bash
# vision-alignment-map.sh — map a single roadmap item to ≥0 vision pillars.
#
# FR-007 / vision-tooling FR-007: LLM-driven semantic match. NO frontmatter
# schema change in V1. Determinism caveat is surfaced by the renderer
# (vision-alignment-render.sh) — this helper just emits the pillar ids.
#
# Mock-injection (CLAUDE.md Rule 5): if KILN_TEST_MOCK_LLM_DIR is set, this
# script reads ${KILN_TEST_MOCK_LLM_DIR}/<basename-of-item>.txt and emits its
# content verbatim — no claude --print invocation.
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme B —
#           vision-alignment-map.sh"
#
# Usage:   vision-alignment-map.sh <item-path>
# Stdout:  zero or more lines, each a single pillar id (slug-form).
#          Sorted ASC. Empty stdout = Drifter (no pillars matched).
# Exit:    0 mapping returned (may be empty).
#          1 usage error.
#          4 LLM call failed; caller may treat as Drifter or retry.
set -u
LC_ALL=C
export LC_ALL

ITEM_PATH="${1:-}"

if [ -z "$ITEM_PATH" ]; then
  echo "vision-alignment-map: usage: vision-alignment-map.sh <item-path>" >&2
  exit 1
fi

if [ ! -f "$ITEM_PATH" ]; then
  echo "vision-alignment-map: file not found: $ITEM_PATH" >&2
  exit 1
fi

# Mock-injection path (CLAUDE.md Rule 5) — used by tests AND any consumer that
# wants deterministic mapping for a fixture. The mock fixture file path is
# derived from the BASENAME of the item path.
if [ -n "${KILN_TEST_MOCK_LLM_DIR:-}" ]; then
  base=$(basename "$ITEM_PATH" .md)
  fixture="${KILN_TEST_MOCK_LLM_DIR}/${base}.txt"
  if [ -f "$fixture" ]; then
    # Emit verbatim. The fixture is expected to be one pillar-id per line, sorted.
    cat "$fixture"
    exit 0
  fi
  # Mock dir set but no fixture for this item → treat as Drifter (empty stdout).
  exit 0
fi

# Live LLM path — grounded by read-project-context.sh per PR #157 + plan §0.2.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX_READER="$SCRIPT_DIR/../context/read-project-context.sh"
CTX_JSON=""
if [ -f "$CTX_READER" ]; then
  CTX_JSON=$(bash "$CTX_READER" 2>/dev/null) || CTX_JSON=""
fi

VISION_FILE="${VISION_FILE:-.kiln/vision.md}"
if [ ! -f "$VISION_FILE" ]; then
  echo "vision-alignment-map: $VISION_FILE missing — cannot map without pillars" >&2
  exit 4
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "vision-alignment-map: claude CLI not available — set KILN_TEST_MOCK_LLM_DIR for tests" >&2
  exit 4
fi

# Compose a terse prompt. The LLM emits one pillar id per line — slug-form
# derived from the bullet text under `## Guiding constraints`.
ITEM_BODY=$(cat "$ITEM_PATH")
VISION_BODY=$(cat "$VISION_FILE")

PROMPT=$(cat <<EOF
You are mapping a roadmap item to one or more "vision pillars" — bullets under
the "## Guiding constraints" section of vision.md (and constraint clauses
within "## What it is not"). Emit ZERO OR MORE pillar ids, one per line, sorted
ASC. A pillar id is a slug-form derived from the FIRST dash-prefixed phrase of
each bullet (lowercase, words joined with hyphens, no punctuation).

Emit NOTHING else — no prose, no headers, no explanation. If no pillar
plausibly matches the item, emit an empty response.

VISION:
$VISION_BODY

ITEM:
$ITEM_BODY
EOF
)

# Invoke claude. On any error, exit 4 (caller treats as Drifter).
RESPONSE=$(printf '%s' "$PROMPT" | claude --print 2>/dev/null) || {
  exit 4
}

# Sanitize: strip blank lines, trim whitespace, sort ASC, dedup.
printf '%s\n' "$RESPONSE" | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }' | LC_ALL=C sort -u
