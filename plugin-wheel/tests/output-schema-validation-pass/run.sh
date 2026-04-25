#!/usr/bin/env bash
# T021 — output-schema-validation-pass fixture.
#
# specs/wheel-typed-schema-locality acceptance scenarios covered:
#   User Story 1 — Acceptance Scenario 3 (passing validation, no extra body).
#
# FRs covered:
#   FR-H1-4 (validator silent on success — no stdout, no stderr)
#   FR-H1-8 (legacy step without output_schema → silent no-op, no log line)
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
# Fixture 1: correctly-shaped output → silent rc=0 (FR-H1-4).
# -----------------------------------------------------------------------------
echo '{"issue_file":"/tmp/issue.md"}' > "$OUT"
STEP='{"id":"good","output_schema":{"issue_file":"$.issue_file"}}'
stderr_out=$(workflow_validate_output_against_schema "$STEP" "$OUT" 2>&1 1>/tmp/.t021_stdout_$$)
rc=$?
stdout_out=$(cat /tmp/.t021_stdout_$$); rm -f /tmp/.t021_stdout_$$

if [[ "$rc" -eq 0 ]]; then
  assert_pass "T1 — exit 0 on passing validation"
else
  assert_fail "T1 — expected exit 0, got $rc"
fi

if [[ -z "$stderr_out" ]]; then
  assert_pass "T2 — FR-H1-4: silent on success (no stderr)"
else
  assert_fail "T2 — FR-H1-4 violated: stderr emitted on pass: $stderr_out"
fi

if [[ -z "$stdout_out" ]]; then
  assert_pass "T3 — FR-H1-4: silent on success (no stdout)"
else
  assert_fail "T3 — FR-H1-4 violated: stdout emitted on pass: $stdout_out"
fi

# -----------------------------------------------------------------------------
# Fixture 2: multi-key schema, all keys present.
# -----------------------------------------------------------------------------
echo '{"alpha":1,"beta":2,"gamma":3}' > "$OUT"
STEP2='{"id":"multi","output_schema":{"alpha":"$.alpha","beta":"$.beta","gamma":"$.gamma"}}'
stderr_out=$(workflow_validate_output_against_schema "$STEP2" "$OUT" 2>&1 1>/dev/null)
rc=$?
if [[ "$rc" -eq 0 && -z "$stderr_out" ]]; then
  assert_pass "T4 — multi-key schema with full match passes silently"
else
  assert_fail "T4 — multi-key match: rc=$rc stderr=$stderr_out"
fi

# -----------------------------------------------------------------------------
# Fixture 3 (FR-H1-8): legacy step with NO output_schema → early-return 0.
# -----------------------------------------------------------------------------
echo '{"anything":"goes"}' > "$OUT"
STEP3='{"id":"legacy"}'
stderr_out=$(workflow_validate_output_against_schema "$STEP3" "$OUT" 2>&1 1>/dev/null)
rc=$?
if [[ "$rc" -eq 0 && -z "$stderr_out" ]]; then
  assert_pass "T5 — FR-H1-8: legacy step (no output_schema) → silent rc=0"
else
  assert_fail "T5 — FR-H1-8 violated: rc=$rc stderr=$stderr_out"
fi

# -----------------------------------------------------------------------------
# Fixture 4 (FR-H1-8 + spec edge case): empty output_schema {} → silent rc=0.
# -----------------------------------------------------------------------------
STEP4='{"id":"empty","output_schema":{}}'
stderr_out=$(workflow_validate_output_against_schema "$STEP4" "$OUT" 2>&1 1>/dev/null)
rc=$?
if [[ "$rc" -eq 0 && -z "$stderr_out" ]]; then
  assert_pass "T6 — empty output_schema {} → silent rc=0 (back-compat)"
else
  assert_fail "T6 — empty schema not silent: rc=$rc stderr=$stderr_out"
fi

# -----------------------------------------------------------------------------
# Fixture 5 (spec edge case): output_schema null → silent rc=0.
# -----------------------------------------------------------------------------
STEP5='{"id":"null_schema","output_schema":null}'
stderr_out=$(workflow_validate_output_against_schema "$STEP5" "$OUT" 2>&1 1>/dev/null)
rc=$?
if [[ "$rc" -eq 0 && -z "$stderr_out" ]]; then
  assert_pass "T7 — null output_schema → silent rc=0"
else
  assert_fail "T7 — null schema not silent: rc=$rc stderr=$stderr_out"
fi

rm -rf "$TMP"

echo
echo "==> output-schema-validation-pass: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
