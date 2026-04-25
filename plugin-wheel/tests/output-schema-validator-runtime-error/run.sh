#!/usr/bin/env bash
# T022 — output-schema-validator-runtime-error fixture.
#
# specs/wheel-typed-schema-locality acceptance scenarios covered:
#   User Story 4 — both Acceptance Scenarios (validator runtime error).
#
# FRs covered:
#   FR-H1-7 (reason=output-schema-validator-error, distinct body, NOT silent
#            fallthrough)
# NFR coverage:
#   NFR-H-7 (loud failure on validator runtime errors)
#   NFR-H-2 (mutation tripwire — silent-fallthrough variant)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"

# shellcheck source=../../lib/workflow.sh
source "${WHEEL_LIB_DIR}/workflow.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d)
OUT="$TMP/output.json"

# -----------------------------------------------------------------------------
# Fixture 1: output_file is not valid JSON → exit 2 with parse-error body.
# -----------------------------------------------------------------------------
echo "this is not valid json {{{" > "$OUT"
STEP='{"id":"malformed-step","output_schema":{"issue_file":"$.issue_file"}}'

stderr_out=$(workflow_validate_output_against_schema "$STEP" "$OUT" 2>&1 1>/dev/null)
rc=$?

if [[ "$rc" -eq 2 ]]; then
  assert_pass "T1 — FR-H1-7: malformed JSON → exit 2 (validator runtime error)"
else
  assert_fail "T1 — expected exit 2, got $rc; stderr: $stderr_out"
fi

if [[ "$stderr_out" == *"Output schema validator error in step 'malformed-step':"* ]]; then
  assert_pass "T2 — error body header names step id with distinct prefix"
else
  assert_fail "T2 — error body wrong shape; got: $stderr_out"
fi

if [[ "$stderr_out" == *"output_file is not valid JSON"* ]]; then
  assert_pass "T3 — error body names underlying parse-failure category"
else
  assert_fail "T3 — error category missing; got: $stderr_out"
fi

# Distinct from FR-H1-6 violation reason — must NOT contain "Output schema
# violation" or "Re-write the file".
if [[ "$stderr_out" != *"Output schema violation"* ]]; then
  assert_pass "T4 — runtime-error body distinct from FR-H1-6 violation body"
else
  assert_fail "T4 — runtime-error reused violation header (codes confused)"
fi

# -----------------------------------------------------------------------------
# Fixture 2: output_file does not exist → exit 2 with "not found" body.
# -----------------------------------------------------------------------------
NONEXISTENT="$TMP/never-written.json"
stderr_out=$(workflow_validate_output_against_schema "$STEP" "$NONEXISTENT" 2>&1 1>/dev/null)
rc=$?
if [[ "$rc" -eq 2 ]]; then
  assert_pass "T5 — missing output_file → exit 2"
else
  assert_fail "T5 — missing file: expected exit 2, got $rc"
fi

if [[ "$stderr_out" == *"output_file not found"* ]]; then
  assert_pass "T6 — missing-file body names category"
else
  assert_fail "T6 — missing-file body wrong; got: $stderr_out"
fi

# -----------------------------------------------------------------------------
# Fixture 3 (NFR-H-2 mutation tripwire): mutate the validator to silent-exit-0
# on runtime error. Assert the mutated copy "passes" the malformed input —
# meaning a regression to silent fallthrough WOULD ship green without this
# tripwire. Sister test to T020's tripwire.
# -----------------------------------------------------------------------------
MUTATED="$TMP/workflow_mutated.sh"
cp "${WHEEL_LIB_DIR}/workflow.sh" "$MUTATED"
python3 -c "
import re
src = open('$MUTATED').read()
patched = re.sub(
  r'(workflow_validate_output_against_schema\(\) \{\n  local step_json=\"\\\$1\"\n  local output_file_path=\"\\\$2\"\n)',
  r'\1  return 0  # NFR-H-2 mutation: silently swallow validator runtime errors\n',
  src, count=1
)
open('$MUTATED', 'w').write(patched)
"

echo "this is not valid json {{{" > "$OUT"
mutated_rc=$(
  source "$MUTATED"
  workflow_validate_output_against_schema "$STEP" "$OUT" 2>/dev/null
  echo "$?"
)
if [[ "$mutated_rc" == "0" ]]; then
  assert_pass "T7 — NFR-H-2 tripwire: silent-fallthrough validator returns 0 on malformed JSON (regression would ship green)"
else
  assert_fail "T7 — mutation didn't take; rc=$mutated_rc"
fi

# Control: real validator on same input still exits 2.
real_rc=$(
  workflow_validate_output_against_schema "$STEP" "$OUT" 2>/dev/null
  echo "$?"
)
if [[ "$real_rc" == "2" ]]; then
  assert_pass "T8 — NFR-H-2 control: real validator still exits 2 on malformed JSON"
else
  assert_fail "T8 — real validator regressed: rc=$real_rc"
fi

rm -rf "$TMP"

echo
echo "==> output-schema-validator-runtime-error: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
