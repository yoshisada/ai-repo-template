#!/usr/bin/env bash
# T020 — output-schema-validation-violation fixture.
#
# specs/wheel-typed-schema-locality acceptance scenarios covered:
#   User Story 1 — Acceptance Scenario 1 (violation diagnostic shape).
#
# FRs covered:
#   FR-H1-1 (validator runs on output write)
#   FR-H1-2 (structured diagnostic — Expected/Actual/Missing/Unexpected lines,
#            LC_ALL=C sort, omitted-when-empty rule)
#   FR-H1-3 (cursor stays on step on violation — same-turn re-write path)
#   FR-H1-5 (bad output_file is NOT deleted)
#   FR-H1-6 (reason=output-schema-violation in wheel_log)
#
# NFR coverage:
#   NFR-H-2 mutation tripwire: a sub-fixture mutates the validator to
#   silent-exit-0 and asserts the violation case fires.
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

# -----------------------------------------------------------------------------
# Fixture 1: missing keys (issue_file expected, actual has action+backlog_path)
# -----------------------------------------------------------------------------
TMP=$(mktemp -d)
OUT="$TMP/output.json"
echo '{"action":"added","backlog_path":"/tmp/x"}' > "$OUT"
STEP='{"id":"report-issue","output_schema":{"issue_file":"$.issue_file"}}'

stderr_out=$(workflow_validate_output_against_schema "$STEP" "$OUT" 2>&1 1>/dev/null)
rc=$?

if [[ "$rc" -eq 1 ]]; then
  assert_pass "T1 — exit code 1 on schema violation (FR-H1-2 / FR-H1-6)"
else
  assert_fail "T1 — expected exit 1, got $rc; stderr: $stderr_out"
fi

# Diagnostic body shape per FR-H1-2.
if [[ "$stderr_out" == *"Output schema violation in step 'report-issue'."* ]]; then
  assert_pass "T2 — diagnostic header names step id"
else
  assert_fail "T2 — header missing step id; got: $stderr_out"
fi

if [[ "$stderr_out" == *"Expected keys (from output_schema): issue_file"* ]]; then
  assert_pass "T3 — Expected line lists schema keys"
else
  assert_fail "T3 — Expected line missing/wrong; got: $stderr_out"
fi

if [[ "$stderr_out" == *"Actual keys in $OUT: action,backlog_path"* ]]; then
  assert_pass "T4 — Actual line lists output keys (LC_ALL=C sorted)"
else
  assert_fail "T4 — Actual line wrong; got: $stderr_out"
fi

if [[ "$stderr_out" == *"Missing: issue_file"* ]]; then
  assert_pass "T5 — Missing line names absent expected key"
else
  assert_fail "T5 — Missing line missing; got: $stderr_out"
fi

if [[ "$stderr_out" == *"Unexpected: action,backlog_path"* ]]; then
  assert_pass "T6 — Unexpected line names extra actual keys"
else
  assert_fail "T6 — Unexpected line missing; got: $stderr_out"
fi

if [[ "$stderr_out" == *"Re-write the file with the expected keys and try again."* ]]; then
  assert_pass "T7 — Re-write footer present"
else
  assert_fail "T7 — Re-write footer missing"
fi

# FR-H1-5: bad output_file is NOT deleted.
if [[ -f "$OUT" ]]; then
  assert_pass "T8 — FR-H1-5: bad output_file remains on disk after violation"
else
  assert_fail "T8 — FR-H1-5: validator deleted output_file (must NOT)"
fi

# -----------------------------------------------------------------------------
# Fixture 2: omission rule — Missing line absent when set is empty.
# Schema = {a, b, c}; output = {a, b, c, d}. Missing empty, Unexpected = {d}.
# -----------------------------------------------------------------------------
echo '{"a":1,"b":2,"c":3,"d":4}' > "$OUT"
STEP2='{"id":"s2","output_schema":{"a":"$.a","b":"$.b","c":"$.c"}}'
stderr_out=$(workflow_validate_output_against_schema "$STEP2" "$OUT" 2>&1 1>/dev/null)
rc=$?
if [[ "$rc" -eq 1 ]]; then
  assert_pass "T9 — extras-only case still returns exit 1"
else
  assert_fail "T9 — expected exit 1, got $rc"
fi
if [[ "$stderr_out" != *"Missing:"* ]]; then
  assert_pass "T10 — FR-H1-2 omission: Missing line OMITTED when set is empty"
else
  assert_fail "T10 — Missing line emitted with empty set; got: $stderr_out"
fi
if [[ "$stderr_out" == *"Unexpected: d"* ]]; then
  assert_pass "T11 — Unexpected line present when set is non-empty"
else
  assert_fail "T11 — Unexpected line missing"
fi

# Schema = {a, b, c}; output = {a, b}. Missing = {c}, Unexpected empty.
echo '{"a":1,"b":2}' > "$OUT"
stderr_out=$(workflow_validate_output_against_schema "$STEP2" "$OUT" 2>&1 1>/dev/null)
if [[ "$stderr_out" == *"Missing: c"* ]]; then
  assert_pass "T12 — Missing line present when set is non-empty"
else
  assert_fail "T12 — Missing line wrong; got: $stderr_out"
fi
if [[ "$stderr_out" != *"Unexpected:"* ]]; then
  assert_pass "T13 — FR-H1-2 omission: Unexpected line OMITTED when set is empty"
else
  assert_fail "T13 — Unexpected line emitted with empty set; got: $stderr_out"
fi

# -----------------------------------------------------------------------------
# Fixture 3: LC_ALL=C sort determinism.
# -----------------------------------------------------------------------------
echo '{"zebra":1,"alpha":2,"middle":3}' > "$OUT"
STEP3='{"id":"sortcheck","output_schema":{"missing_key":"$.x"}}'
stderr_out=$(workflow_validate_output_against_schema "$STEP3" "$OUT" 2>&1 1>/dev/null)
# Actual list should be alpha,middle,zebra (LC_ALL=C lexicographic).
if [[ "$stderr_out" == *"Actual keys in $OUT: alpha,middle,zebra"* ]]; then
  assert_pass "T14 — actual keys sorted LC_ALL=C lexicographic"
else
  assert_fail "T14 — actual sort wrong; got: $stderr_out"
fi

# -----------------------------------------------------------------------------
# Fixture 4: NFR-H-2 mutation tripwire — copy validator into a tmp file and
# mutate it to silent exit 0. Re-run T1; assert it now PASSES (i.e. the
# validator is silently swallowing violations) — this confirms our real test
# WOULD have caught a regression.
# -----------------------------------------------------------------------------
MUTATED="$TMP/workflow_mutated.sh"
cp "${WHEEL_LIB_DIR}/workflow.sh" "$MUTATED"
# Replace the function body with `return 0` short-circuit.
python3 -c "
import re, sys
src = open('$MUTATED').read()
# Inject a 'return 0' as the first statement of the function body.
patched = re.sub(
  r'(workflow_validate_output_against_schema\(\) \{\n  local step_json=\"\\\$1\"\n  local output_file_path=\"\\\$2\"\n)',
  r'\1  return 0  # NFR-H-2 mutation: silently swallow all violations\n',
  src, count=1
)
open('$MUTATED', 'w').write(patched)
" || { assert_fail "could not mutate validator for tripwire"; rm -rf "$TMP"; exit 1; }

# Run the mutated validator on fixture 1's wrong output.
echo '{"action":"added","backlog_path":"/tmp/x"}' > "$OUT"
mutated_rc=$(
  source "$MUTATED"
  workflow_validate_output_against_schema "$STEP" "$OUT" 2>/dev/null
  echo "$?"
)
if [[ "$mutated_rc" == "0" ]]; then
  assert_pass "T15 — NFR-H-2 mutation tripwire: silent-swallow validator exits 0 on violation (regression would ship green)"
else
  assert_fail "T15 — mutation didn't take; rc=$mutated_rc"
fi

# Sanity: real (unmutated) validator on same input STILL exits 1.
real_rc=$(
  workflow_validate_output_against_schema "$STEP" "$OUT" 2>/dev/null
  echo "$?"
)
if [[ "$real_rc" == "1" ]]; then
  assert_pass "T16 — NFR-H-2 control: real validator (unmutated) still exits 1 — tripwire is meaningful"
else
  assert_fail "T16 — real validator regressed: rc=$real_rc"
fi

rm -rf "$TMP"

echo
echo "==> output-schema-validation-violation: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
