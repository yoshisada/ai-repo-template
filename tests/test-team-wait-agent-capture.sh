#!/usr/bin/env bash
# Test: team-wait PostToolUse captures Agent spawns and updates teammate status
# Simulates the PostToolUse hook flow after an Agent tool is called
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

export WHEEL_LIB_DIR="$REPO_DIR/plugin-wheel/lib"
source "$WHEEL_LIB_DIR/engine.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# Setup: create temp dir for test state
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

STATE_FILE="$TMPDIR/state.json"
WORKFLOW_FILE="$REPO_DIR/workflows/tests/team-static.json"

echo "=== Test 1: team-wait captures Agent spawn and constructs agent_id ==="

# Load workflow
WORKFLOW=$(workflow_load "$WORKFLOW_FILE")

# Create initial state at cursor 5 (team-wait step)
state_init "$STATE_FILE" "$WORKFLOW" "test-session-123" "" "$WORKFLOW_FILE"

# Simulate: team-create recorded, 3 teammates registered, cursor at team-wait
state_set_team "$STATE_FILE" "create-team" "test-static-team"
state_add_teammate "$STATE_FILE" "create-team" "worker-1" "" "" ".wheel/outputs/team-test-static-team/worker-1" '{"worker_id":1}'
state_add_teammate "$STATE_FILE" "create-team" "worker-2" "" "" ".wheel/outputs/team-test-static-team/worker-2" '{"worker_id":2}'
state_add_teammate "$STATE_FILE" "create-team" "worker-3" "" "" ".wheel/outputs/team-test-static-team/worker-3" '{"worker_id":3}'

# Mark steps 0-4 as done, set cursor to 5
for i in 0 1 2 3 4; do
  state_set_step_status "$STATE_FILE" "$i" "done"
done
state_set_cursor "$STATE_FILE" 5
state_set_step_status "$STATE_FILE" 5 "working"

# Verify initial state: all teammates pending with empty agent_id
state=$(state_read "$STATE_FILE")
w1_status=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-1"].status')
w1_aid=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-1"].agent_id')
assert_eq "worker-1 initial status" "pending" "$w1_status"
assert_eq "worker-1 initial agent_id" "" "$w1_aid"

# Simulate PostToolUse for Agent tool call spawning worker-1
engine_init "$WORKFLOW_FILE" "$STATE_FILE"
MOCK_HOOK_INPUT='{"tool_name":"Agent","tool_input":{"name":"worker-1","team_name":"test-static-team","subagent_type":"wheel-runner"},"session_id":"test-session-123","agent_id":""}'
engine_handle_hook "post_tool_use" "$MOCK_HOOK_INPUT" > /dev/null

# Check: worker-1 should be "running" with agent_id "worker-1@test-static-team"
state=$(state_read "$STATE_FILE")
w1_status=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-1"].status')
w1_aid=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-1"].agent_id')
assert_eq "worker-1 status after Agent spawn" "running" "$w1_status"
assert_eq "worker-1 agent_id after Agent spawn" "worker-1@test-static-team" "$w1_aid"

# Simulate spawning worker-2 and worker-3
MOCK_HOOK_INPUT2='{"tool_name":"Agent","tool_input":{"name":"worker-2","team_name":"test-static-team"},"session_id":"test-session-123","agent_id":""}'
MOCK_HOOK_INPUT3='{"tool_name":"Agent","tool_input":{"name":"worker-3","team_name":"test-static-team"},"session_id":"test-session-123","agent_id":""}'
engine_handle_hook "post_tool_use" "$MOCK_HOOK_INPUT2" > /dev/null
engine_handle_hook "post_tool_use" "$MOCK_HOOK_INPUT3" > /dev/null

state=$(state_read "$STATE_FILE")
w2_status=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-2"].status')
w2_aid=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-2"].agent_id')
w3_status=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-3"].status')
w3_aid=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-3"].agent_id')
assert_eq "worker-2 status" "running" "$w2_status"
assert_eq "worker-2 agent_id" "worker-2@test-static-team" "$w2_aid"
assert_eq "worker-3 status" "running" "$w3_status"
assert_eq "worker-3 agent_id" "worker-3@test-static-team" "$w3_aid"

echo ""
echo "=== Test 2: alternate_agent_id mapping finds running teammates ==="

# Simulate what post-tool-use.sh does when a worker activates its sub-workflow
# It looks for running teammates with agent_ids to claim
_tids=$(jq -r '
  [.teams // {} | to_entries[] | .value.teammates // {} | to_entries[] |
   select(.value.status == "running") | .value.agent_id // empty] | .[]
' "$STATE_FILE" 2>/dev/null) || true

tid_count=$(echo "$_tids" | grep -c '.' || true)
assert_eq "running teammate IDs found" "3" "$tid_count"

# Check that the IDs are the expected team-format IDs
echo "$_tids" | grep -q "worker-1@test-static-team" && assert_eq "worker-1 ID in list" "found" "found" || assert_eq "worker-1 ID in list" "found" "missing"
echo "$_tids" | grep -q "worker-2@test-static-team" && assert_eq "worker-2 ID in list" "found" "found" || assert_eq "worker-2 ID in list" "found" "missing"
echo "$_tids" | grep -q "worker-3@test-static-team" && assert_eq "worker-3 ID in list" "found" "found" || assert_eq "worker-3 ID in list" "found" "missing"

echo ""
echo "=== Test 3: SubagentStop marks teammate completed ==="

# Simulate SubagentStop for worker-1
MOCK_STOP_INPUT='{"name":"worker-1","agent_id":"worker-1@test-static-team","session_id":"test-session-123"}'
engine_handle_hook "subagent_stop" "$MOCK_STOP_INPUT" > /dev/null

state=$(state_read "$STATE_FILE")
w1_status=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-1"].status')
assert_eq "worker-1 status after SubagentStop" "completed" "$w1_status"

# worker-2 and worker-3 still running
w2_status=$(echo "$state" | jq -r '.teams["create-team"].teammates["worker-2"].status')
assert_eq "worker-2 still running" "running" "$w2_status"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
