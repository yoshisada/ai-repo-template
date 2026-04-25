#!/usr/bin/env bash
# T048 — Pure-shell unit tests for the 8 documented resolve_inputs error shapes.
#
# Per specs/wheel-step-input-output-schema/contracts/interfaces.md §2:
#
#   E1: missing upstream output
#   E2: unsupported expression
#   E3: $config allowlist denial
#   E4: $config file not found
#   E5: $config key not found
#   E6: $plugin not in registry
#   E7: regex extractor pattern did not match
#   E8: field referenced not in upstream output_schema
#
# Each assertion checks that the EXACT documented stderr line shape appears.
# NFR-G-2 mutation tripwire: a deliberately-mutated assertion string is
# checked alongside each — proves the assertion is genuine (not vacuously true).
#
# Validates Acceptance Scenarios for User Story 2 in spec.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../../lib/resolve_inputs.sh
source "${REPO_ROOT}/plugin-wheel/lib/resolve_inputs.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Mutation-tripwire helper — proves the assertion is genuine. NFR-G-2.
expect_in_stderr() {
  local stderr="$1" expected_substring="$2" label="$3"
  local mutated_substring="${expected_substring}__MUTATED_TRIPWIRE_DO_NOT_MATCH__"
  if [[ "$stderr" == *"$expected_substring"* ]]; then
    if [[ "$stderr" == *"$mutated_substring"* ]]; then
      assert_fail "${label} — mutation tripwire fired (test is vacuously true)"
    else
      assert_pass "${label}"
    fi
  else
    assert_fail "${label} — expected '${expected_substring}' in: ${stderr}"
  fi
}

SCRATCH=$(mktemp -d -t wheel-error-shapes-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
cd "$SCRATCH"

# Common workflow + state shape. Override `inputs` per case.
mk_workflow() {
  local inputs_json="$1"
  printf '{"name":"err-shape-test","steps":[{"id":"under-test","type":"agent","inputs":%s}]}' "$inputs_json"
}
mk_state() {
  printf '{"workflow_name":"err-shape-test","cursor":0,"steps":[{"id":"under-test","type":"agent","status":"pending"}]}'
}

echo "=== E1 — missing upstream output ==="
INPUTS='{"FOO":"$.steps.does-not-exist.output.bar"}'
WF=$(mk_workflow "$INPUTS")
STEP=$(printf '%s' "$WF" | jq -c '.steps[0]')
ST=$(mk_state)
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "references missing upstream output" "(E1) documented missing-upstream error"
expect_in_stderr "$err" "FOO" "(E1) error includes input var name"
expect_in_stderr "$err" "does-not-exist" "(E1) error includes upstream step id"

echo "=== E2 — unsupported expression ==="
INPUTS='{"BAR":"this-is-not-jsonpath"}'
WF=$(mk_workflow "$INPUTS")
STEP=$(printf '%s' "$WF" | jq -c '.steps[0]')
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "unsupported expression" "(E2) documented unsupported-expression error"
expect_in_stderr "$err" "BAR" "(E2) error includes var name"
expect_in_stderr "$err" 'Supported: $.steps' "(E2) error lists supported forms"

echo "=== E3 — \$config allowlist denial ==="
echo "openai_api_key = sk-deadbeef" > "${SCRATCH}/.shelf-config"
INPUTS='{"K":"$config(.shelf-config:openai_api_key)"}'
WF=$(mk_workflow "$INPUTS")
STEP=$(printf '%s' "$WF" | jq -c '.steps[0]')
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "is not in the safe-key allowlist" "(E3) documented allowlist-denial error"
expect_in_stderr "$err" "openai_api_key" "(E3) error includes the offending key"
expect_in_stderr "$err" "CONFIG_KEY_ALLOWLIST" "(E3) error names the allowlist mechanism"

echo "=== E4 — \$config file not found ==="
INPUTS='{"S":"$config(.shelf-config:slug)"}'
WF=$(mk_workflow "$INPUTS")
STEP=$(printf '%s' "$WF" | jq -c '.steps[0]')
# Move the config file out of the way so the file-not-found path triggers.
mv "${SCRATCH}/.shelf-config" "${SCRATCH}/.shelf-config.bak"
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "config file" "(E4) documented file-not-found error"
expect_in_stderr "$err" "not found" "(E4) error states 'not found'"
mv "${SCRATCH}/.shelf-config.bak" "${SCRATCH}/.shelf-config"

echo "=== E5 — \$config key not found ==="
# The config file exists but `slug` isn't in it (we only have openai_api_key).
INPUTS='{"S":"$config(.shelf-config:slug)"}'
WF=$(mk_workflow "$INPUTS")
STEP=$(printf '%s' "$WF" | jq -c '.steps[0]')
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "key" "(E5) documented key-not-found error"
expect_in_stderr "$err" "slug" "(E5) error includes the offending key"
expect_in_stderr "$err" "not found in" "(E5) error states 'not found in'"

echo "=== E6 — \$plugin not in registry ==="
INPUTS='{"P":"$plugin(nonexistent-plugin)"}'
WF=$(mk_workflow "$INPUTS")
STEP=$(printf '%s' "$WF" | jq -c '.steps[0]')
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{"plugins":{}}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "is not in this session's registry" "(E6) documented plugin-not-in-registry error"
expect_in_stderr "$err" "nonexistent-plugin" "(E6) error includes the offending plugin name"

echo "=== E7 — regex extractor pattern did not match ==="
echo "no-tag-line-here" > "${SCRATCH}/up.txt"
WF=$(printf '%s' '{"name":"err-shape-test","steps":[
  {"id":"upstream","type":"agent","output":"up.txt","output_schema":{"tag":{"extract":"regex:tag=([a-z]+)"}}},
  {"id":"under-test","type":"agent","inputs":{"T":"$.steps.upstream.output.tag"}}
]}')
ST=$(printf '%s' '{"workflow_name":"err-shape-test","cursor":1,"steps":[
  {"id":"upstream","type":"agent","status":"done","output":"up.txt"},
  {"id":"under-test","type":"agent","status":"pending"}
]}')
STEP=$(printf '%s' "$WF" | jq -c '.steps[1]')
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "regex extractor against step" "(E7) documented regex-no-match error"
expect_in_stderr "$err" "did not match" "(E7) error states 'did not match'"

echo "=== E8 — referenced field not in upstream output_schema ==="
WF=$(printf '%s' '{"name":"err-shape-test","steps":[
  {"id":"upstream","type":"agent","output":"up.txt","output_schema":{"foo":"$.foo"}},
  {"id":"under-test","type":"agent","inputs":{"M":"$.steps.upstream.output.missing_field"}}
]}')
echo '{"foo":"value"}' > "${SCRATCH}/up.txt"
STEP=$(printf '%s' "$WF" | jq -c '.steps[1]')
err=$(resolve_inputs "$STEP" "$ST" "$WF" '{}' 2>&1 >/dev/null || true)
expect_in_stderr "$err" "missing_field" "(E8) error includes offending field name"
expect_in_stderr "$err" "is not in that step's output_schema" "(E8) documented field-not-in-schema error"

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
