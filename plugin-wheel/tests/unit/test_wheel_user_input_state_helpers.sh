#!/usr/bin/env bash
# FR-003/FR-004/FR-008 (wheel-user-input): state_set_awaiting_user_input and
# state_clear_awaiting_user_input round-trip correctness, idempotency, atomic
# replacement.
#
# Covers US1 (set/clear behavior) and US4 (clear after skip).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"

# shellcheck source=../../lib/state.sh
source "${PLUGIN_DIR}/lib/state.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Create a scratch state file.
scratch_dir="$(mktemp -d -t wheel-state-helpers.XXXXXX)"
trap 'rm -rf "$scratch_dir"' EXIT
state_file="${scratch_dir}/state_test.json"
jq -n '{
  workflow_name: "t", workflow_version: "1", workflow_file: "t.json",
  status: "running", cursor: 0,
  owner_session_id: "sid", owner_agent_id: "",
  started_at: "2026-04-24T00:00:00.000Z",
  updated_at: "2026-04-24T00:00:00.000Z",
  steps: [
    {id: "s0", type: "agent", status: "working"},
    {id: "s1", type: "agent", status: "pending"}
  ]
}' > "$state_file"

# --- Case 1: set writes all three fields ---
state_set_awaiting_user_input "$state_file" 0 "need phase assignment"
awaiting=$(jq -r '.steps[0].awaiting_user_input' "$state_file")
since=$(jq -r '.steps[0].awaiting_user_input_since' "$state_file")
reason=$(jq -r '.steps[0].awaiting_user_input_reason' "$state_file")
if [[ "$awaiting" == "true" ]] && [[ "$since" =~ ^20[0-9]{2}- ]] && [[ "$reason" == "need phase assignment" ]]; then
  assert_pass "state_set_awaiting_user_input writes all three fields"
else
  assert_fail "set: awaiting=$awaiting since=$since reason=$reason"
fi

# --- Case 2: set affects only the targeted step ---
other_awaiting=$(jq -r '.steps[1].awaiting_user_input // false' "$state_file")
if [[ "$other_awaiting" == "false" ]]; then
  assert_pass "set leaves sibling steps untouched"
else
  assert_fail "set leaked into steps[1]: $other_awaiting"
fi

# --- Case 3: clear resets all three fields ---
state_clear_awaiting_user_input "$state_file" 0
awaiting=$(jq -r '.steps[0].awaiting_user_input' "$state_file")
since=$(jq -r '.steps[0].awaiting_user_input_since' "$state_file")
reason=$(jq -r '.steps[0].awaiting_user_input_reason' "$state_file")
if [[ "$awaiting" == "false" ]] && [[ "$since" == "null" ]] && [[ "$reason" == "null" ]]; then
  assert_pass "state_clear_awaiting_user_input resets all three fields"
else
  assert_fail "clear: awaiting=$awaiting since=$since reason=$reason"
fi

# --- Case 4: clear is idempotent on already-clear step ---
if state_clear_awaiting_user_input "$state_file" 1 2>/dev/null; then
  assert_pass "clear is idempotent (never-set step)"
else
  assert_fail "clear failed on already-clear step"
fi

# --- Case 5: set round-trips (write then read) on a different step ---
state_set_awaiting_user_input "$state_file" 1 "second reason"
reason1=$(jq -r '.steps[1].awaiting_user_input_reason' "$state_file")
if [[ "$reason1" == "second reason" ]]; then
  assert_pass "set/clear round-trip works on arbitrary step index"
else
  assert_fail "round-trip: reason=$reason1"
fi

# --- Case 6: atomic write — no partial state observable ---
# Validate JSON remains parseable after every mutation (proxy for atomicity).
if jq empty "$state_file" 2>/dev/null; then
  assert_pass "state file is always valid JSON after mutations"
else
  assert_fail "state file is not valid JSON after mutations"
fi

# --- Case 7: updated_at is bumped ---
before_ts=$(jq -r '.updated_at' "$state_file")
sleep 1
state_set_awaiting_user_input "$state_file" 0 "another reason"
after_ts=$(jq -r '.updated_at' "$state_file")
if [[ "$before_ts" != "$after_ts" ]]; then
  assert_pass "set bumps updated_at"
else
  assert_fail "updated_at not bumped by set ($before_ts -> $after_ts)"
fi

# --- Case 8: missing state file errors out ---
if state_set_awaiting_user_input "/nonexistent/path.json" 0 "r" 2>/dev/null; then
  assert_fail "set should fail on nonexistent file"
else
  assert_pass "set errors on missing state file"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
