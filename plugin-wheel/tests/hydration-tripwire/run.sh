#!/usr/bin/env bash
# T049 — Pure-shell unit tests for the hydration tripwire (FR-G3-5).
#
# Validates Acceptance Scenario 4 of User Story 2 in spec.md:
#   "Given a residual {{VAR}} after substitution (input declared but
#    referenced incorrectly), When the tripwire scan runs, Then the step
#    fails with the documented 'residual placeholder' error."
#
# Pattern under test: `\{\{[A-Z][A-Z0-9_]*\}\}` (uppercase-leading per
# plan §3.D — ensures lowercase / mixed-case `{{...}}` template literals
# don't false-positive).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../../lib/preprocess.sh
source "${REPO_ROOT}/plugin-wheel/lib/preprocess.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

echo "=== (T1) Tripwire fires on undeclared placeholder ==="
INSTR='Use {{ISSUE_FILE}} which we never declared.'
RESOLVED='{}'
if substitute_inputs_into_instruction "$INSTR" "$RESOLVED" "step-x" 2>/dev/null; then
  assert_fail "(T1) tripwire SHOULD have fired"
else
  err=$(substitute_inputs_into_instruction "$INSTR" "$RESOLVED" "step-x" 2>&1 >/dev/null || true)
  if [[ "$err" == *"Hydration tripwire fired on step 'step-x'"* \
     && "$err" == *"residual placeholder"* \
     && "$err" == *"{{ISSUE_FILE}}"* ]]; then
    assert_pass "(T1) tripwire error includes step id + residual placeholder name"
  else
    assert_fail "(T1) wrong tripwire error: $err"
  fi
fi

echo "=== (T2) Tripwire fires on partially-resolved (some declared, one residual) ==="
INSTR='File {{KNOWN}} and unknown {{UNKNOWN}}.'
RESOLVED='{"KNOWN":"foo.md"}'
if substitute_inputs_into_instruction "$INSTR" "$RESOLVED" "step-y" 2>/dev/null; then
  assert_fail "(T2) tripwire SHOULD have fired on UNKNOWN"
else
  err=$(substitute_inputs_into_instruction "$INSTR" "$RESOLVED" "step-y" 2>&1 >/dev/null || true)
  if [[ "$err" == *"{{UNKNOWN}}"* ]]; then
    assert_pass "(T2) tripwire identifies UNKNOWN as residual"
  else
    assert_fail "(T2) tripwire missing UNKNOWN: $err"
  fi
fi

echo "=== (T3) Tripwire does NOT fire on lowercase {{var}} (different namespace) ==="
INSTR='Mustache template {{lowercase}} should pass through.'
RESOLVED='{}'
out=$(substitute_inputs_into_instruction "$INSTR" "$RESOLVED" "step-z" 2>/dev/null) || {
  assert_fail "(T3) tripwire FALSE-positived on lowercase"
  out="<errored>"
}
if [[ "$out" == "$INSTR" ]]; then
  assert_pass "(T3) lowercase {{var}} preserved byte-identically"
fi

echo "=== (T4) Tripwire does NOT fire on mixed-case {{Var}} ==="
INSTR='Mixed {{CamelCase}} stays.'
out=$(substitute_inputs_into_instruction "$INSTR" '{}' "step-z2" 2>/dev/null) || {
  assert_fail "(T4) tripwire false-positive on mixed-case"
  out="<errored>"
}
[[ "$out" == "$INSTR" ]] && assert_pass "(T4) mixed-case {{Var}} preserved"

echo "=== (T5) Multiple residual placeholders all reported ==="
INSTR='{{A}}, {{B}}, and {{C}} all undeclared.'
err=$(substitute_inputs_into_instruction "$INSTR" '{}' "step-multi" 2>&1 >/dev/null || true)
if [[ "$err" == *"{{A}}"* && "$err" == *"{{B}}"* && "$err" == *"{{C}}"* ]]; then
  assert_pass "(T5) all 3 residuals named in error"
else
  assert_fail "(T5) some residuals missing from error: $err"
fi

echo "=== (T6) Successful substitution → no tripwire fire ==="
INSTR='Use {{NAME}} please.'
out=$(substitute_inputs_into_instruction "$INSTR" '{"NAME":"world"}' "step-ok" 2>/dev/null) || {
  assert_fail "(T6) substitution unexpectedly failed"
  out=""
}
if [[ "$out" == "Use world please." ]]; then
  assert_pass "(T6) happy-path substitution + tripwire passes"
else
  assert_fail "(T6) wrong substitution output: '$out'"
fi

echo "=== (T7) NFR-G-2 mutation tripwire — bogus assertion does not match ==="
err=$(substitute_inputs_into_instruction "{{NEVER_DECLARED}}" '{}' "step-nfr" 2>&1 >/dev/null || true)
bogus="this string is intentionally not present 12345"
if [[ "$err" == *"$bogus"* ]]; then
  assert_fail "(T7) mutation tripwire — bogus matched (test is vacuous)"
else
  assert_pass "(T7) mutation tripwire — assertion is genuine"
fi

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
