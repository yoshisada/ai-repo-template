#!/usr/bin/env bash
# Test: roadmap-coached-interview-basic
#
# Validates: User Story 1 Acceptance Scenarios 1–4 (coached interview with
#            orientation, suggested answers, and accept-all).
#
# Acceptance scenarios this validates:
#   - AS 1: orientation block precedes Question 1 (FR-006).
#   - AS 2: each question renders with proposed answer + rationale + affordance
#           (FR-004).
#   - AS 3: `accept-all` finalizes item (FR-005).
#   - AS 4: `tweak <value> then accept-all` finalizes with override (FR-005).
#
# This is a STATIC CHECK against SKILL.md — it asserts the prompt structure is
# in place. A behavioral test lives under the /kiln:kiln-test harness and is
# driven by the test.yaml in this directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-roadmap/SKILL.md"

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: SKILL.md missing at $SKILL" >&2
  exit 1
fi

pass=0
fail=0

assert_contains() {
  local what="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$SKILL"; then
    echo "  ok: SKILL.md contains '$what'"
    pass=$((pass + 1))
  else
    echo "  FAIL: SKILL.md does NOT contain '$what' (looking for: $pattern)" >&2
    fail=$((fail + 1))
  fi
}

echo "Checking coached-interview markers in SKILL.md..."

# FR-006: orientation block marker
assert_contains "orientation block (FR-006)" "orientation"

# FR-006: mentions nearby items, current phase, open critiques
assert_contains "orientation cites current phase"     "current phase"
assert_contains "orientation cites nearby items"      "nearby items"
assert_contains "orientation cites open critiques"    "open critiques"

# FR-004: per-question coached rendering
assert_contains "coached question affordance"         "[accept"
assert_contains "rationale label"                     "Why:"
assert_contains "proposed-answer label"               "Proposed:"

# FR-005: accept-all + tweak-then-accept-all
assert_contains "accept-all"                          "accept-all"
assert_contains "tweak-then-accept-all"               "tweak"

# FR-007: collaborative framing
assert_contains "collaborative framing"               "Here's what I think"

# Reader invocation
assert_contains "reader invocation"                   "read-project-context.sh"

if [[ "$fail" -gt 0 ]]; then
  echo ""
  echo "FAIL: roadmap-coached-interview-basic — $fail missing markers ($pass passed)" >&2
  exit 1
fi

echo ""
echo "PASS: roadmap-coached-interview-basic — all $pass markers present"
