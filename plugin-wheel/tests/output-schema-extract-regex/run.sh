#!/usr/bin/env bash
# T051 — Pure-shell unit tests for output_schema regex extractor (FR-G1-2).
#
# Validates Acceptance Scenarios for User Story 1 + edge-case table entry
# "regex extract directive matches multiple times → first match wins".
#
# Tests the BASH `extract_output_field` helper (used by workflow_validate +
# external test fixtures). The python3-backed `resolve_inputs` runtime path
# uses an equivalent re.search(MULTILINE) — the same semantics are verified
# end-to-end via resolve-inputs-error-shapes (E7).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../../lib/resolve_inputs.sh
source "${REPO_ROOT}/plugin-wheel/lib/resolve_inputs.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

echo "=== (R1) Positive — regex with capture group, single match ==="
SCHEMA='{"tag":{"extract":"regex:tag=([a-z]+)"}}'
OUT="header line\ntag=success\nfooter line"
val=$(extract_output_field "$OUT" "$SCHEMA" "tag" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == "success" ]]; then
  assert_pass "(R1) capture group #1 returned"
else
  assert_fail "(R1) expected 'success', got '$val' (rc=$rc)"
fi

echo "=== (R2) Positive — regex without capture group returns whole match ==="
SCHEMA='{"path":{"extract":"regex:\\.kiln/issues/[^\\s]+\\.md"}}'
OUT="some prose\n.kiln/issues/2026-04-25-foo.md\nmore prose"
val=$(extract_output_field "$OUT" "$SCHEMA" "path" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == ".kiln/issues/2026-04-25-foo.md" ]]; then
  assert_pass "(R2) whole match returned when no capture group"
else
  assert_fail "(R2) expected the .kiln/issues path, got '$val' (rc=$rc)"
fi

echo "=== (R3) Multi-match — first match wins ==="
SCHEMA='{"item":{"extract":"regex:item=([a-z]+)"}}'
OUT="item=alpha\nitem=beta\nitem=gamma"
val=$(extract_output_field "$OUT" "$SCHEMA" "item" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$val" == "alpha" ]]; then
  assert_pass "(R3) first match wins (I-EX-1 / contract §3 table)"
else
  assert_fail "(R3) expected 'alpha', got '$val' (rc=$rc)"
fi

echo "=== (R4) Negative — no match → loud failure ==="
SCHEMA='{"x":{"extract":"regex:never_matches_anything"}}'
OUT="some text without the pattern"
if extract_output_field "$OUT" "$SCHEMA" "x" >/dev/null 2>&1; then
  assert_fail "(R4) should have failed on no-match"
else
  err=$(extract_output_field "$OUT" "$SCHEMA" "x" 2>&1 >/dev/null || true)
  if [[ "$err" == *"regex"*"did not match"* ]]; then
    assert_pass "(R4) no-match → loud failure with documented error"
  else
    assert_fail "(R4) wrong error: $err"
  fi
fi

echo "=== (R5) Negative — empty upstream output ==="
SCHEMA='{"x":{"extract":"regex:foo"}}'
if extract_output_field "" "$SCHEMA" "x" >/dev/null 2>&1; then
  assert_fail "(R5) should have failed on empty input"
else
  assert_pass "(R5) empty input → failure"
fi

echo "=== (R6) Negative — malformed extract directive ==="
SCHEMA='{"x":{"extract":"unsupported:foo"}}'
if extract_output_field "any" "$SCHEMA" "x" >/dev/null 2>&1; then
  assert_fail "(R6) should have failed on unsupported directive"
else
  err=$(extract_output_field "any" "$SCHEMA" "x" 2>&1 >/dev/null || true)
  if [[ "$err" == *"malformed extract directive"* ]]; then
    assert_pass "(R6) unsupported directive → loud failure"
  else
    assert_fail "(R6) wrong error: $err"
  fi
fi

echo "=== (R7) NFR-G-2 mutation tripwire — bogus assertion does not match ==="
err=$(extract_output_field "x" '{"x":{"extract":"regex:never"}}' "x" 2>&1 >/dev/null || true)
bogus="this string is intentionally not present 12345"
if [[ "$err" == *"$bogus"* ]]; then
  assert_fail "(R7) mutation tripwire — bogus matched (vacuous)"
else
  assert_pass "(R7) mutation tripwire — assertion genuine"
fi

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
