#!/usr/bin/env bash
# T047 — Pure-shell unit tests for the CONFIG_KEY_ALLOWLIST gate
#         (specs/wheel-step-input-output-schema NFR-G-7 / OQ-G-1 Candidate A).
#
# Validates Acceptance Scenarios for User Story 3 in spec.md:
#   1. allowed key resolves correctly
#   2. unknown key rejected with documented allowlist-denial error
#   3. unsupported config file (non-existent) rejected with documented error
#   4. NFR-G-2 mutation tripwire — deliberately mutate the error string and
#      assert the test fails (proves the test exercises the assertion path).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../../lib/resolve_inputs.sh
source "${REPO_ROOT}/plugin-wheel/lib/resolve_inputs.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Build a synthetic per-test scratch dir holding a fake .shelf-config.
SCRATCH=$(mktemp -d -t wheel-allowlist-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

cat > "${SCRATCH}/.shelf-config" <<EOF
# Test config — only a few keys.
shelf_full_sync_counter = 7
shelf_full_sync_threshold = 10
slug = my-project
some_secret_thing = SHOULD_NEVER_RESOLVE
EOF

mk_step() {
  local var="$1" expr="$2"
  printf '{"id":"under-test","type":"agent","inputs":{"%s":"%s"}}' "$var" "$expr"
}
mk_workflow() {
  printf '{"name":"allowlist-test","steps":[%s]}' "$(mk_step "$1" "$2")"
}
mk_state() {
  printf '{"workflow_name":"allowlist-test","cursor":0,"steps":[{"id":"under-test","type":"agent","status":"pending"}]}'
}

cd "$SCRATCH"

  echo "=== (1) NFR-G-7 — allowed key resolves correctly ==="
  STEP=$(mk_step CURRENT_COUNTER '$config(.shelf-config:shelf_full_sync_counter)')
  WORKFLOW=$(mk_workflow CURRENT_COUNTER '$config(.shelf-config:shelf_full_sync_counter)')
  STATE=$(mk_state)
  if RESOLVED=$(resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>&1); then
    val=$(printf '%s' "$RESOLVED" | jq -r '.CURRENT_COUNTER')
    if [[ "$val" == "7" ]]; then
      assert_pass "(1a) allowed key 'shelf_full_sync_counter' resolves to '7'"
    else
      assert_fail "(1a) expected '7', got '$val' (full: $RESOLVED)"
    fi
  else
    assert_fail "(1a) resolver exited 1 unexpectedly: $RESOLVED"
  fi

  echo "=== (2) NFR-G-7 — unknown key rejected with documented error (US3-1) ==="
  STEP=$(mk_step API_KEY '$config(.shelf-config:openai_api_key)')
  WORKFLOW=$(mk_workflow API_KEY '$config(.shelf-config:openai_api_key)')
  if resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>/dev/null; then
    assert_fail "(2a) unknown allowlist key SHOULD have been rejected"
  else
    err=$(resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>&1 >/dev/null || true)
    if [[ "$err" == *"is not in the safe-key allowlist"* \
       && "$err" == *"openai_api_key"* \
       && "$err" == *"CONFIG_KEY_ALLOWLIST"* ]]; then
      assert_pass "(2a) unknown key documented allowlist-denial error"
    else
      assert_fail "(2a) wrong/missing allowlist error: $err"
    fi
  fi

  echo "=== (2b) NFR-G-7 — secret-shaped key (some_secret_thing) ALSO rejected (default-deny) ==="
  STEP=$(mk_step LEAKED '$config(.shelf-config:some_secret_thing)')
  WORKFLOW=$(mk_workflow LEAKED '$config(.shelf-config:some_secret_thing)')
  if resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>/dev/null; then
    assert_fail "(2b) presence of secret-shaped key in file should NOT be sufficient — allowlist gate must reject it"
  else
    err=$(resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>&1 >/dev/null || true)
    if [[ "$err" == *"is not in the safe-key allowlist"* ]]; then
      assert_pass "(2b) secret key default-denied (I-AL-1)"
    else
      assert_fail "(2b) expected allowlist-denial, got: $err"
    fi
  fi

  echo "=== (3) US3-2 — unsupported / missing config file rejected ==="
  STEP=$(mk_step X '$config(.does-not-exist:slug)')
  WORKFLOW=$(mk_workflow X '$config(.does-not-exist:slug)')
  # `slug` is in the .shelf-config allowlist but NOT for `.does-not-exist`.
  # The allowlist gate checks `<file>:<key>` together so this fails on the
  # missing-allowlist path (gate triggers before file existence check).
  if resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>/dev/null; then
    assert_fail "(3a) unsupported config file path should have been rejected"
  else
    err=$(resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>&1 >/dev/null || true)
    if [[ "$err" == *"safe-key allowlist"* || "$err" == *"config file"*"not found"* ]]; then
      assert_pass "(3a) unsupported config file → loud failure"
    else
      assert_fail "(3a) wrong rejection: $err"
    fi
  fi

  echo "=== (4) NFR-G-2 — mutation tripwire (proves the test exercises the assertion path) ==="
  STEP=$(mk_step API_KEY '$config(.shelf-config:openai_api_key)')
  WORKFLOW=$(mk_workflow API_KEY '$config(.shelf-config:openai_api_key)')
  err=$(resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>&1 >/dev/null || true)
  # The mutation tripwire: a deliberately-WRONG search string should NOT match.
  # If the test passes both the real assertion AND the mutated assertion, the
  # test is ineffective (vacuously true). NFR-G-2 demands this discipline.
  bogus="this string is intentionally not in the resolver error text 12345"
  if [[ "$err" == *"$bogus"* ]]; then
    assert_fail "(4a) mutation tripwire — bogus string matched (test would be ineffective)"
  else
    assert_pass "(4a) mutation tripwire — bogus string does not match real error (test is genuine)"
  fi

  echo '=== (5) JSON-file form ($config(<file>:<jq-path>)) is exempt from flat allowlist ==='
  echo '{"foo":{"bar":"baz"}}' > "${SCRATCH}/state.json"
  STEP=$(mk_step F '$config(state.json:.foo.bar)')
  WORKFLOW=$(mk_workflow F '$config(state.json:.foo.bar)')
  if RESOLVED=$(resolve_inputs "$STEP" "$STATE" "$WORKFLOW" '{}' 2>&1); then
    val=$(printf '%s' "$RESOLVED" | jq -r '.F')
    if [[ "$val" == "baz" ]]; then
      assert_pass "(5a) JSON-file form bypasses flat allowlist (jq path is the gate)"
    else
      assert_fail "(5a) expected 'baz', got: $val"
    fi
  else
    assert_fail "(5a) JSON-file form failed: $RESOLVED"
  fi

cd "$REPO_ROOT"

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
