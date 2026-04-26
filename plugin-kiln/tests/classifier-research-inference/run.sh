#!/usr/bin/env bash
# T013 / SC-001 / FR-013 / FR-014 — classifier research-block inference fixture.
# Asserts:
#   1. "cheaper" descriptions produce research_inference with cost+tokens axes.
#   2. "faster" descriptions produce time axis.
#   3. Descriptions without signal words emit NO research_inference key (NOT
#      null, NOT {}) — structural absence per NFR-006 sibling.
# Substrate: tier-2 (run.sh-only). Invoke directly:
#   bash plugin-kiln/tests/classifier-research-inference/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/plugin-kiln/scripts/roadmap/classify-description.sh"

[[ -x "$CLASSIFIER" ]] || { echo "FAIL: classifier not executable"; exit 2; }

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

case_cheaper() {
  local out
  out=$(bash "$CLASSIFIER" "make claude-md-audit cheaper")
  printf '%s' "$out" | jq -e '.research_inference.proposed_axes | any(.metric == "cost") and any(.metric == "tokens")' >/dev/null
}
assert "'cheaper' → cost + tokens axes" case_cheaper

case_faster() {
  local out
  out=$(bash "$CLASSIFIER" "the audit should be faster")
  printf '%s' "$out" | jq -e '.research_inference.proposed_axes | any(.metric == "time" and .direction == "lower")' >/dev/null
}
assert "'faster' → time:lower axis" case_faster

case_no_signal() {
  local out
  out=$(bash "$CLASSIFIER" "build a new feature for users")
  # Structural absence — research_inference must NOT be present at all.
  printf '%s' "$out" | jq -e 'has("research_inference") | not' >/dev/null
}
assert "no signal → research_inference absent (NFR-006 sibling)" case_no_signal

case_priority_default() {
  local out
  out=$(bash "$CLASSIFIER" "make this faster")
  # Default priority: primary on every inferred axis.
  printf '%s' "$out" | jq -e '.research_inference.proposed_axes | all(.priority == "primary")' >/dev/null
}
assert "every inferred axis defaults priority: primary" case_priority_default

case_matched_signals() {
  local out
  out=$(bash "$CLASSIFIER" "make claude-md-audit cheaper")
  printf '%s' "$out" | jq -e '.research_inference.matched_signals | index("cheaper") != null' >/dev/null
}
assert "matched_signals records 'cheaper'" case_matched_signals

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
