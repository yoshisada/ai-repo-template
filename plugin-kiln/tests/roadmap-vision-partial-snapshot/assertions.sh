#!/usr/bin/env bash
# Assertions for roadmap-vision-partial-snapshot (T021).
# Validates FR-012 + Clarification #4: partial snapshot → partial draft with per-section
# evidence annotations; NO blank-slate banner.
# Acceptance: User Story 2 Scenario 5.
set -euo pipefail

VISION=".kiln/vision.md"
if [[ ! -f "$VISION" ]]; then
  echo "FAIL: $VISION not written from partial snapshot" >&2
  exit 1
fi

# Must have all four sections
for section in "What we are building" "What it is not" "How we'll know we're winning" "Guiding constraints"; do
  if ! grep -qF "## $section" "$VISION"; then
    echo "FAIL: partial draft lost section '$section'" >&2
    exit 1
  fi
done

# Must contain at least one per-section evidence annotation. We accept either:
#   - "derived from: docs/features/..." (positive citation)
#   - "(no roadmap items yet)" / "(no CLAUDE.md)" (negative annotation — missing evidence)
# At least ONE of these markers per run.
if ! grep -qE '(derived from|from PRD|from README|\(no [a-z]+ (yet|available|present)\))' "$VISION"; then
  echo "FAIL: partial snapshot draft lacks per-section evidence annotations (FR-012)" >&2
  cat "$VISION" >&2
  exit 1
fi

# Must NOT contain the blank-slate banner text. The canonical phrase is "blank-slate"
# — if it appears in the vision body, the skill mis-routed a partial case as fully-empty.
if grep -qi "blank-slate" "$VISION"; then
  echo "FAIL: partial snapshot emitted blank-slate banner — violates Clarification #4" >&2
  exit 1
fi

echo "PASS: partial snapshot produced annotated vision without blank-slate banner" >&2
exit 0
