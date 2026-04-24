#!/usr/bin/env bash
# Test: roadmap-coached-interview-quick
#
# Validates: NFR-005 (backward compat — `--quick` skips orientation and
#            interview byte-for-byte vs pre-change behavior) and
#            User Story 1 Acceptance Scenario 5.
#
# This is a STATIC CHECK: the `--quick` routing in SKILL.md must short-circuit
# the coached layer. We assert two structural invariants:
#   1. `--quick` continues to gate the adversarial interview (Step 5).
#   2. `--quick` continues to gate the orientation / coaching block.
#
# The behavioral byte-identical assertion is a golden-file regression — see
# the /kiln:kiln-test fixture (test.yaml) — this static check is a cheap
# tripwire that catches the majority of accidental coupling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-roadmap/SKILL.md"

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: SKILL.md missing at $SKILL" >&2
  exit 1
fi

# Existing `--quick` guard on the adversarial interview (Step 5).
if ! grep -Fq 'Skip the entire interview when `QUICK_MODE == 1`' "$SKILL"; then
  echo "FAIL: --quick must still skip the adversarial interview (Step 5)" >&2
  exit 1
fi

# New guard: orientation block must be skipped under --quick.
# Accept either explicit 'skip ... orientation' or an early-return marker.
if ! grep -Eiq "QUICK_MODE.*orientation|orientation.*QUICK_MODE|skip.*orientation|orientation.*skip" "$SKILL"; then
  echo "FAIL: --quick must short-circuit the orientation block (NFR-005)" >&2
  exit 1
fi

# Follow-up loop still gated by --quick (no regression).
if ! grep -Fq 'Skip the follow-up loop entirely when `QUICK_MODE == 1`' "$SKILL"; then
  echo "FAIL: --quick follow-up loop guard removed (NFR-005 regression)" >&2
  exit 1
fi

echo "PASS: roadmap-coached-interview-quick — --quick still short-circuits the coached layer"
