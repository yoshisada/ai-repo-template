#!/usr/bin/env bash
# Assertions for roadmap-vision-first-run (T018).
# Validates FR-008: populated repo + no vision → all four sections drafted with evidence citations.
# Acceptance Scenario: User Story 2 Scenario 1.
set -euo pipefail

VISION=".kiln/vision.md"

if [[ ! -f "$VISION" ]]; then
  echo "FAIL: $VISION was not written" >&2
  exit 1
fi

# Required section headers (matches templates/vision-template.md structure)
for section in "What we are building" "What it is not" "How we'll know we're winning" "Guiding constraints"; do
  if ! grep -qF "## $section" "$VISION"; then
    echo "FAIL: section '## $section' missing from $VISION" >&2
    echo "--- file contents ---" >&2
    cat "$VISION" >&2
    exit 1
  fi
done

# At least one evidence citation must appear (derived from / from roadmap item / from PRD)
if ! grep -qE '(derived from|from PRD|from roadmap item|see docs/features/|see \.kiln/roadmap/)' "$VISION"; then
  echo "FAIL: no evidence citations found in vision draft (FR-008 requires per-bullet citations)" >&2
  echo "--- file contents ---" >&2
  cat "$VISION" >&2
  exit 1
fi

# last_updated: frontmatter present and stamped (not the literal template placeholder)
if ! head -5 "$VISION" | grep -qE '^last_updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "FAIL: last_updated frontmatter missing or not ISO-date stamped" >&2
  head -5 "$VISION" >&2
  exit 1
fi

echo "PASS: vision first-run draft has all four sections with evidence + stamped last_updated" >&2
exit 0
