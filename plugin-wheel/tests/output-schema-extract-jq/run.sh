#!/usr/bin/env bash
# T052 — Pure-shell unit tests for output_schema jq + direct-JSON-path
#         extractors (FR-G1-2).
#
# Validates Acceptance Scenarios for User Story 1 (positive direct-JSON-path
# extraction) + edge-cases.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../../lib/resolve_inputs.sh
source "${REPO_ROOT}/plugin-wheel/lib/resolve_inputs.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

echo "=== (J1) Direct JSON-path positive — \$.foo ==="
SCHEMA='{"file":"$.file"}'
OUT='{"file":"/path/to/foo.md","extra":"value"}'
val=$(extract_output_field "$OUT" "$SCHEMA" "file" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == "/path/to/foo.md" ]]; then
  assert_pass "(J1) direct \$.file extracted"
else
  assert_fail "(J1) expected '/path/to/foo.md', got '$val' (rc=$rc)"
fi

echo "=== (J2) Direct JSON-path nested — \$.foo.bar ==="
SCHEMA='{"deep":"$.foo.bar"}'
OUT='{"foo":{"bar":"baz","ignored":"x"}}'
val=$(extract_output_field "$OUT" "$SCHEMA" "deep" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == "baz" ]]; then
  assert_pass "(J2) nested path extracted"
else
  assert_fail "(J2) expected 'baz', got '$val' (rc=$rc)"
fi

echo "=== (J3) Direct JSON-path field missing — null → loud failure ==="
SCHEMA='{"x":"$.missing_field"}'
OUT='{"present":"yes"}'
if extract_output_field "$OUT" "$SCHEMA" "x" >/dev/null 2>&1; then
  assert_fail "(J3) should have failed on missing field"
else
  err=$(extract_output_field "$OUT" "$SCHEMA" "x" 2>&1 >/dev/null || true)
  if [[ "$err" == *"resolved to null"* || "$err" == *"missing"* || "$err" == *"null"* ]]; then
    assert_pass "(J3) missing field → loud failure"
  else
    assert_fail "(J3) wrong error: $err"
  fi
fi

echo "=== (J4) Direct JSON-path on non-JSON output → loud failure ==="
SCHEMA='{"x":"$.field"}'
OUT="this is plain text, not JSON"
if extract_output_field "$OUT" "$SCHEMA" "x" >/dev/null 2>&1; then
  assert_fail "(J4) should have failed on non-JSON input"
else
  assert_pass "(J4) non-JSON → loud failure"
fi

echo "=== (J5) jq directive positive — top-level field ==="
SCHEMA='{"f":{"extract":"jq:.field"}}'
OUT='{"field":"value-here"}'
val=$(extract_output_field "$OUT" "$SCHEMA" "f" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == "value-here" ]]; then
  assert_pass "(J5) jq directive extracted"
else
  assert_fail "(J5) expected 'value-here', got '$val' (rc=$rc)"
fi

echo "=== (J6) jq directive nested ==="
SCHEMA='{"f":{"extract":"jq:.outer.inner"}}'
OUT='{"outer":{"inner":"deep"}}'
val=$(extract_output_field "$OUT" "$SCHEMA" "f" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == "deep" ]]; then
  assert_pass "(J6) nested jq path extracted"
else
  assert_fail "(J6) expected 'deep', got '$val' (rc=$rc)"
fi

echo "=== (J7) Negative — referenced field not in schema (caller-side check) ==="
SCHEMA='{"only_field":"$.x"}'
OUT='{"x":1}'
if extract_output_field "$OUT" "$SCHEMA" "missing" >/dev/null 2>&1; then
  assert_fail "(J7) should have failed when field not in schema"
else
  err=$(extract_output_field "$OUT" "$SCHEMA" "missing" 2>&1 >/dev/null || true)
  if [[ "$err" == *"not in upstream output_schema"* || "$err" == *"missing"* ]]; then
    assert_pass "(J7) field-not-in-schema → loud failure"
  else
    assert_fail "(J7) wrong error: $err"
  fi
fi

echo "=== (J8) Negative — jq parse failure ==="
SCHEMA='{"f":{"extract":"jq:.field"}}'
OUT="not valid json"
if extract_output_field "$OUT" "$SCHEMA" "f" >/dev/null 2>&1; then
  assert_fail "(J8) should have failed on jq parse error"
else
  assert_pass "(J8) jq parse failure → loud failure"
fi

echo "=== (J9) NFR-G-2 mutation tripwire ==="
err=$(extract_output_field 'invalid' '{"x":"$.foo"}' "x" 2>&1 >/dev/null || true)
bogus="this string is intentionally not present 12345"
if [[ "$err" == *"$bogus"* ]]; then
  assert_fail "(J9) mutation tripwire — bogus matched (vacuous)"
else
  assert_pass "(J9) mutation tripwire — assertion genuine"
fi

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
