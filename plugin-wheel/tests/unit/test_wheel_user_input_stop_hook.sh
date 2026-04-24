#!/usr/bin/env bash
# FR-007/FR-008/FR-009 (wheel-user-input): Stop hook integration — silence
# branch when awaiting_user_input=true, auto-clear on advance, and FR-009
# instruction-injection via context_build.
#
# This is a bash-level integration test: it invokes stop.sh with a crafted
# hook input and a seeded state file, then asserts the hook's stdout and the
# resulting state mutation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

scratch="$(mktemp -d -t wheel-stop-hook.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
mkdir -p .wheel workflows

# --- Case 1: stop hook is silent when awaiting_user_input=true ---
wf="${scratch}/workflows/wf1.json"
jq -n '{
  name: "wf1", version: "1",
  steps: [{id: "s0", type: "agent", output: "out.json", instruction: "do the thing", allow_user_input: true}]
}' > "$wf"
state="${scratch}/.wheel/state_SID_aid1.json"
jq -n --arg wf "$wf" '{
  workflow_name: "wf1", workflow_version: "1", workflow_file: $wf,
  status: "running", cursor: 0,
  owner_session_id: "SID", owner_agent_id: "aid1",
  started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
  steps: [{id: "s0", type: "agent", status: "working",
           awaiting_user_input: true,
           awaiting_user_input_since: "2026-04-24T00:00:00Z",
           awaiting_user_input_reason: "need user"}]
}' > "$state"

hook_input=$(jq -nc '{session_id: "SID", agent_id: "aid1"}')
# Run stop.sh — it should emit minimal silent JSON.
output=$(printf '%s' "$hook_input" | bash "${PLUGIN_DIR}/hooks/stop.sh" 2>/dev/null) && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  # Must be {"decision": "approve"} with NO stopReason / additionalContext / systemMessage.
  decision=$(printf '%s' "$output" | jq -r '.decision // empty' 2>/dev/null || echo "")
  has_extra=$(printf '%s' "$output" | jq -r '(.stopReason // .additionalContext // .systemMessage // empty)' 2>/dev/null || echo "")
  if [[ "$decision" == "approve" ]] && [[ -z "$has_extra" ]]; then
    assert_pass "stop hook is silent (decision=approve, no extra fields) when awaiting_user_input=true (FR-007)"
  else
    assert_fail "silent branch produced unexpected output: $output"
  fi
else
  assert_fail "stop hook exited non-zero (rc=$rc) in silent branch: $output"
fi

# State must remain unchanged (awaiting_user_input still true, cursor still 0).
awaiting_after=$(jq -r '.steps[0].awaiting_user_input' "$state")
cursor_after=$(jq -r '.cursor' "$state")
if [[ "$awaiting_after" == "true" ]] && [[ "$cursor_after" == "0" ]]; then
  assert_pass "silent branch leaves state unchanged"
else
  assert_fail "silent branch mutated state: awaiting=$awaiting_after cursor=$cursor_after"
fi

# --- Case 2: writing the output file auto-clears awaiting_user_input on advance ---
# Simulate the agent writing the output file and firing the stop hook again —
# the hook should detect the output, clear the flag, and advance.
echo '{"answer": "42"}' > "${scratch}/out.json"
output=$(printf '%s' "$hook_input" | bash "${PLUGIN_DIR}/hooks/stop.sh" 2>/dev/null) && rc=0 || rc=$?

awaiting_after=$(jq -r '.steps[0].awaiting_user_input' "$state")
since_after=$(jq -r '.steps[0].awaiting_user_input_since' "$state")
reason_after=$(jq -r '.steps[0].awaiting_user_input_reason' "$state")
status_after=$(jq -r '.steps[0].status' "$state")

if [[ "$awaiting_after" == "false" ]] && [[ "$since_after" == "null" ]] && [[ "$reason_after" == "null" ]]; then
  assert_pass "advance auto-clears awaiting_user_input/_since/_reason (FR-008)"
else
  assert_fail "post-advance: awaiting=$awaiting_after since=$since_after reason=$reason_after"
fi
if [[ "$status_after" == "done" ]]; then
  assert_pass "advance transitions step to done"
else
  assert_fail "advance status: expected done, got $status_after"
fi

# --- Case 3: FR-009 instruction injection via context_build ---
# Source the lib and call context_build directly on a step with
# allow_user_input: true; verify the injected block is present.
export WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
# shellcheck source=../../lib/context.sh
source "${PLUGIN_DIR}/lib/context.sh"
step_json=$(jq -nc '{id: "s0", type: "agent", instruction: "ask the user", allow_user_input: true}')
state_json=$(jq -nc '{steps: [{id: "s0", status: "working"}]}')
workflow_json=$(jq -nc '{name: "t", steps: [{id: "s0", type: "agent", allow_user_input: true}]}')
context_out=$(context_build "$step_json" "$state_json" "$workflow_json")
if [[ "$context_out" == *"This step permits user input"* ]] \
   && [[ "$context_out" == *"wheel flag-needs-input"* ]] \
   && [[ "$context_out" == *"Stop hook will stay silent"* ]]; then
  assert_pass "context_build appends FR-009 block when allow_user_input: true"
else
  assert_fail "FR-009 block missing from context: $context_out"
fi

# --- Case 4: FR-009 block NOT appended when allow_user_input is absent ---
step_json2=$(jq -nc '{id: "s1", type: "agent", instruction: "just do it"}')
context_out2=$(context_build "$step_json2" "$state_json" "$workflow_json")
if [[ "$context_out2" != *"This step permits user input"* ]]; then
  assert_pass "context_build does NOT append FR-009 block when allow_user_input is absent"
else
  assert_fail "FR-009 block wrongly appended on non-permissive step"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
