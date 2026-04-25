#!/usr/bin/env bash
# T022 — Pure-shell unit tests for plugin-wheel/lib/resolve_inputs.sh::_parse_jsonpath_expr
#
# Validates Acceptance Scenario 3 of User Story 1 (positive parsing) AND
# Acceptance Scenario 3 of User Story 2 (malformed JSONPath fails) per
# specs/wheel-step-input-output-schema/spec.md.
#
# FRs covered: FR-G2-1 ($.steps), FR-G2-2 ($config), FR-G2-3 ($plugin),
#              FR-G2-4 ($step), FR-G2-5 (anything else fails loud).
#
# Contract: specs/wheel-step-input-output-schema/contracts/interfaces.md §1.
#
# Per plan.md §2 / NFR-G-1 carveout: pure-shell unit tests are acceptable
# for resolver/hydration logic without an LLM in the loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../../lib/resolve_inputs.sh
source "${REPO_ROOT}/plugin-wheel/lib/resolve_inputs.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Positive helper: parse + check kind/arg1/arg2.
# Acceptance Scenario US1-3 (interfaces.md §1 grammar table).
expect_parse() {
  local expr="$1" want_kind="$2" want_a1="$3" want_a2="$4" label="$5"
  if _parse_jsonpath_expr "$expr"; then
    if [[ "$_PARSED_KIND" == "$want_kind" \
       && "$_PARSED_ARG1" == "$want_a1" \
       && "$_PARSED_ARG2" == "$want_a2" ]]; then
      assert_pass "$label"
    else
      assert_fail "$label — kind=$_PARSED_KIND a1=$_PARSED_ARG1 a2=$_PARSED_ARG2 (expected $want_kind/$want_a1/$want_a2)"
    fi
  else
    assert_fail "$label — parser rejected: ${_PARSED_ERROR:-?}"
  fi
}

# Negative helper: must return non-zero (FR-G2-5 "anything else fails loud").
# Acceptance Scenario US2-3.
expect_reject() {
  local expr="$1" label="$2"
  if _parse_jsonpath_expr "$expr"; then
    assert_fail "$label — should have rejected, got kind=$_PARSED_KIND"
  else
    assert_pass "$label"
  fi
}

# Idempotency helper (I-PJ-2): two calls produce the same globals.
expect_idempotent() {
  local expr="$1"
  _parse_jsonpath_expr "$expr" >/dev/null 2>&1 || true
  local k1="$_PARSED_KIND" a1="$_PARSED_ARG1" b1="$_PARSED_ARG2"
  _parse_jsonpath_expr "$expr" >/dev/null 2>&1 || true
  if [[ "$k1" == "$_PARSED_KIND" && "$a1" == "$_PARSED_ARG1" && "$b1" == "$_PARSED_ARG2" ]]; then
    assert_pass "(idempotent) two calls return identical globals for '$expr'"
  else
    assert_fail "(idempotent) drift detected on '$expr'"
  fi
}

echo "=== FR-G2-1 — \$.steps.<id>.output.<field> (positive) ==="
expect_parse '$.steps.write-issue-note.output.issue_file' \
  "dollar_steps" "write-issue-note" "issue_file" \
  "(p1) hyphenated step id + underscored field"
expect_parse '$.steps.create_issue.output.path' \
  "dollar_steps" "create_issue" "path" \
  "(p2) underscored step id"
expect_parse '$.steps.s.output.f' \
  "dollar_steps" "s" "f" \
  "(p3) single-char step id + field"

echo "=== FR-G2-2 — \$config(<file>:<key>) (positive) ==="
expect_parse '$config(.shelf-config:shelf_full_sync_counter)' \
  "dollar_config" ".shelf-config" "shelf_full_sync_counter" \
  "(p4) flat shelf-config key"
expect_parse '$config(.shelf-config:slug)' \
  "dollar_config" ".shelf-config" "slug" \
  "(p5) short key"
expect_parse '$config(.kiln/state.json:.foo.bar)' \
  "dollar_config" ".kiln/state.json" ".foo.bar" \
  "(p6) JSON file with jq path"

echo "=== FR-G2-3 — \$plugin(<name>) (positive) ==="
expect_parse '$plugin(shelf)' \
  "dollar_plugin" "shelf" "" \
  "(p7) bare plugin name"
expect_parse '$plugin(plugin-wheel)' \
  "dollar_plugin" "plugin-wheel" "" \
  "(p8) hyphenated plugin name"
expect_parse '$plugin(my_plugin_2)' \
  "dollar_plugin" "my_plugin_2" "" \
  "(p9) alphanumeric plugin name"

echo "=== FR-G2-4 — \$step(<step-id>) (positive) ==="
expect_parse '$step(write-issue-note)' \
  "dollar_step" "write-issue-note" "" \
  "(p10) hyphenated step id"
expect_parse '$step(check_existing)' \
  "dollar_step" "check_existing" "" \
  "(p11) underscored step id"

echo "=== FR-G2-5 — anything else fails loud (negative) ==="
# Acceptance scenarios from US2-3 — "malformed JSONPath fails with documented error".
expect_reject '$.steps.foo.output.bar.extra' \
  "(n1) extra path segment after .output.<field>"
expect_reject '$config(missing-paren' \
  "(n2) missing closing paren on \$config"
expect_reject '$.STEPS.foo.output.bar' \
  "(n3) uppercase STEPS prefix (case-sensitive grammar)"
expect_reject '$' \
  "(n4) bare \$ alone"
expect_reject '$$plugin(shelf)' \
  "(n5) double-\$ prefix (preprocess-escape syntax leaks through)"
expect_reject '$plugin()' \
  "(n6) empty plugin name"
expect_reject '' \
  "(n7) empty string"
expect_reject 'random text' \
  "(n8) random string with no \$ prefix"
expect_reject '${WHEEL_PLUGIN_shelf}' \
  "(n9) preprocess-style token (different namespace)"

echo "=== I-PJ-2 — idempotency ==="
expect_idempotent '$.steps.write-issue-note.output.issue_file'
expect_idempotent '$config(.shelf-config:shelf_full_sync_counter)'
expect_idempotent '$plugin(shelf)'
expect_idempotent 'unsupported expression'

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
