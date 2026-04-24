#!/usr/bin/env bash
# Test: roadmap-coached-interview-empty-snapshot
#
# Validates: Edge Case "Roadmap item with unknown/ambiguous fields"
#   — "Coached suggestions must be sourced only from project-context signals,
#      never invented; unknown fields get a `[suggestion: —, rationale: no
#      evidence in repo]` placeholder to preserve tone calibration."
#
# This is a STATIC CHECK that SKILL.md contains the placeholder marker used
# when the project-context reader returns empty fields. No behavioral run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-roadmap/SKILL.md"

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: SKILL.md missing at $SKILL" >&2
  exit 1
fi

# Marker for empty-snapshot placeholder — the skill must not invent values.
if ! grep -F "no evidence in repo" "$SKILL" >/dev/null; then
  echo "FAIL: SKILL.md missing empty-snapshot placeholder ('no evidence in repo')" >&2
  exit 1
fi

# Explicit instruction that the skill must not invent values.
if ! grep -Eiq "(never invent|don't invent|do not invent)" "$SKILL"; then
  echo "FAIL: SKILL.md missing 'never invent values' guardrail (edge-case contract)" >&2
  exit 1
fi

echo "PASS: roadmap-coached-interview-empty-snapshot — placeholder + guardrail present"
