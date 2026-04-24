#!/usr/bin/env bash
# FR-001/FR-002 (wheel-user-input): Validate workflow_validate_allow_user_input
# rejects allow_user_input: true on non-{agent,loop,branch} step types and
# accepts it on permitted step types.
#
# Covers US3 acceptance scenario 2.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"

# shellcheck source=../../lib/workflow.sh
source "${PLUGIN_DIR}/lib/workflow.sh"

pass=0
fail=0
assert_pass() {
  local desc="$1"
  pass=$((pass + 1))
  echo "PASS: $desc"
}
assert_fail() {
  local desc="$1"
  fail=$((fail + 1))
  echo "FAIL: $desc" >&2
}

# --- Case 1: allow_user_input=true on type=agent → accepted ---
good_agent=$(jq -nc '{
  name: "t", version: "1",
  steps: [{id: "s1", type: "agent", allow_user_input: true, output: "x.json", instruction: "i"}]
}')
if workflow_validate_allow_user_input "$good_agent" 2>/dev/null; then
  assert_pass "agent step with allow_user_input: true is accepted"
else
  assert_fail "agent step with allow_user_input: true should be accepted (got rejection)"
fi

# --- Case 2: allow_user_input=true on type=loop → accepted ---
good_loop=$(jq -nc '{
  name: "t", version: "1",
  steps: [{id: "s1", type: "loop", allow_user_input: true, max_iterations: 3, substep: {type: "agent"}}]
}')
if workflow_validate_allow_user_input "$good_loop" 2>/dev/null; then
  assert_pass "loop step with allow_user_input: true is accepted"
else
  assert_fail "loop step with allow_user_input: true should be accepted"
fi

# --- Case 3: allow_user_input=true on type=branch → accepted ---
good_branch=$(jq -nc '{
  name: "t", version: "1",
  steps: [{id: "s1", type: "branch", allow_user_input: true, condition_command: "true"}]
}')
if workflow_validate_allow_user_input "$good_branch" 2>/dev/null; then
  assert_pass "branch step with allow_user_input: true is accepted"
else
  assert_fail "branch step with allow_user_input: true should be accepted"
fi

# --- Case 4: allow_user_input=true on type=command → rejected ---
bad_command=$(jq -nc '{
  name: "t", version: "1",
  steps: [{id: "cmd1", type: "command", command: "echo hi", allow_user_input: true}]
}')
stderr_output=$(workflow_validate_allow_user_input "$bad_command" 2>&1 >/dev/null) && bad_cmd_exit=0 || bad_cmd_exit=$?
if [[ "$bad_cmd_exit" -ne 0 ]]; then
  if [[ "$stderr_output" == *"cmd1"* ]] && [[ "$stderr_output" == *"allow_user_input"* ]]; then
    assert_pass "command step with allow_user_input: true is rejected with informative error"
  else
    assert_fail "rejection message missing step id or field name: $stderr_output"
  fi
else
  assert_fail "command step with allow_user_input: true should be rejected"
fi

# --- Case 5: allow_user_input absent → accepted on any type ---
good_absent=$(jq -nc '{
  name: "t", version: "1",
  steps: [{id: "c", type: "command", command: "echo hi"}, {id: "a", type: "agent", output: "x.json", instruction: "i"}]
}')
if workflow_validate_allow_user_input "$good_absent" 2>/dev/null; then
  assert_pass "absence of allow_user_input accepted on all step types"
else
  assert_fail "absent allow_user_input should be accepted"
fi

# --- Case 6: allow_user_input=false → accepted on any type ---
good_false=$(jq -nc '{
  name: "t", version: "1",
  steps: [{id: "c", type: "command", command: "echo hi", allow_user_input: false}]
}')
if workflow_validate_allow_user_input "$good_false" 2>/dev/null; then
  assert_pass "allow_user_input: false accepted on command step"
else
  assert_fail "allow_user_input: false should be accepted on command step"
fi

# --- Case 7: multiple offenders → all reported ---
multi_bad=$(jq -nc '{
  name: "t", version: "1",
  steps: [
    {id: "c1", type: "command", command: "echo hi", allow_user_input: true},
    {id: "tw", type: "team-wait", team: "tc1", allow_user_input: true}
  ]
}')
stderr_output=$(workflow_validate_allow_user_input "$multi_bad" 2>&1 >/dev/null) && multi_exit=0 || multi_exit=$?
if [[ "$multi_exit" -ne 0 ]] && [[ "$stderr_output" == *"c1"* ]] && [[ "$stderr_output" == *"tw"* ]]; then
  assert_pass "multiple offenders all named in stderr"
else
  assert_fail "multiple offenders case — expected c1 and tw in stderr: $stderr_output"
fi

# --- Case 8: workflow_load integration — rejects via full load path ---
tmp_wf="$(mktemp -t wheel-validator.XXXXXX)"
trap 'rm -f "$tmp_wf"' EXIT
jq -n '{
  name: "bad-wf", version: "1",
  steps: [{id: "c", type: "command", command: "echo hi", allow_user_input: true}]
}' > "$tmp_wf"
if ! workflow_load "$tmp_wf" >/dev/null 2>&1; then
  assert_pass "workflow_load propagates validator rejection"
else
  assert_fail "workflow_load should fail when validator rejects"
fi

# --- Summary ---
echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
