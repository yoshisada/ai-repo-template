#!/usr/bin/env bash
# T019 — SC-010 / FR-006.
# Asserts the regeneration-exhausted bail invariant is documented in /plan
# SKILL.md prose AND that the documented bound matches contract:
#   - default max_regenerations = 3 per fixture
#   - bail message: `Bail out! regeneration-exhausted: fixture-<id> rejected <N> times`
#   - exhaustion happens AFTER max_regenerations + 1 total attempts (1 initial + 3 regens = 4)
# Substrate: tier-2 (run.sh-only). Structural assertion against SKILL.md prose;
# live exhaustion test queues to first-real-use (Phase 1.5 review loop is
# interactive/prose, no extracted helper exposes the counter for direct testing).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL="$REPO_ROOT/plugin-kiln/skills/plan/SKILL.md"
SPEC="$REPO_ROOT/specs/research-first-plan-time-agents/spec.md"

[[ -f "$SKILL" ]] || { echo "FAIL: SKILL.md not at $SKILL"; exit 2; }
[[ -f "$SPEC" ]] || { echo "FAIL: spec.md not at $SPEC"; exit 2; }

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

case_skill_documents_max_regenerations() {
  grep -q -F 'max_regenerations' "$SKILL" \
    && grep -q -F 'default 3' "$SKILL"
}
assert_pass "SKILL.md documents max_regenerations default 3" case_skill_documents_max_regenerations

case_skill_documents_bail_message() {
  grep -q -F 'Bail out! regeneration-exhausted: fixture-<id> rejected <N> times' "$SKILL"
}
assert_pass "SKILL.md documents the regeneration-exhausted bail-out message" case_skill_documents_bail_message

case_skill_documents_overridable() {
  # The frontmatter override path is documented (per FR-006).
  grep -q -E 'frontmatter-overridable|max_regenerations:[[:space:]]*<int>' "$SKILL"
}
assert_pass "SKILL.md documents frontmatter override of max_regenerations" case_skill_documents_overridable

case_spec_anchors_fr_006() {
  grep -q -F 'FR-006' "$SPEC" \
    && grep -q -F 'regeneration-exhausted' "$SPEC"
}
assert_pass "spec.md anchors FR-006 to the regeneration-exhausted bail" case_spec_anchors_fr_006

# The synthesizer agent's regenerate-call handling is documented in agent.md.
case_synth_agent_documents_regenerate() {
  local agent="$REPO_ROOT/plugin-kiln/agents/fixture-synthesizer.md"
  grep -q -F 'regeneration_attempt' "$agent" \
    && grep -q -F 'rejection_reason' "$agent"
}
assert_pass "fixture-synthesizer agent.md documents regenerate-call inputs" case_synth_agent_documents_regenerate

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
