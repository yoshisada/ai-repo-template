#!/usr/bin/env bash
# Test: TeammateIdle detects archived sub-workflow and marks teammate completed
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
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $label"; PASS=$((PASS + 1))
  else echo "  FAIL: $label — expected '$expected', got '$actual'"; FAIL=$((FAIL + 1)); fi
}

echo "=== Test: TeammateIdle marks completed when sub-workflow archived ==="

PARENT=".wheel/state_test_parent_idle.json"
trap "rm -f $PARENT" EXIT

# Create parent state at team-wait with 1 running teammate
WF=$(workflow_load "workflows/tests/team-static.json")
state_init "$PARENT" "$WF" "sess-idle-test" "" "workflows/tests/team-static.json"
state_set_team "$PARENT" "create-team" "idle-test-team"
state_add_teammate "$PARENT" "create-team" "worker-1" "" "worker-1@idle-test-team" "out/w1" '{"id":1}'
state_update_teammate_status "$PARENT" "create-team" "worker-1" "running"
for i in 0 1 2 3 4; do state_set_step_status "$PARENT" "$i" "done"; done
state_set_cursor "$PARENT" 5
state_set_step_status "$PARENT" 5 "working"

# Verify initial state
st=$(state_read "$PARENT")
w1_status=$(echo "$st" | jq -r '.teams["create-team"].teammates["worker-1"].status')
assert_eq "worker-1 initial status" "running" "$w1_status"

# NO worker state file exists — sub-workflow archived

# Simulate TeammateIdle hook for worker-1 (real format has teammate_name + team_name, no agent_id)
HOOK_INPUT='{"session_id":"sess-idle-test","teammate_name":"worker-1","team_name":"idle-test-team","hook_event_name":"TeammateIdle"}'
RESULT=$(echo "$HOOK_INPUT" | bash "$REPO_DIR/plugin-wheel/hooks/teammate-idle.sh" 2>/dev/null)

# Check result
# When all teammates done, team-wait completes and returns continue:false
# When last teammate completes, team-wait finishes and the hook returns continue:false or stopReason
has_stop=$(echo "$RESULT" | jq -r '.stopReason // empty')
assert_eq "hook signals team-wait complete" "true" "$([[ -n "$has_stop" ]] && echo true || echo false)"

# Check parent state — worker-1 should be completed
st=$(state_read "$PARENT")
w1_status=$(echo "$st" | jq -r '.teams["create-team"].teammates["worker-1"].status')
assert_eq "worker-1 marked completed" "completed" "$w1_status"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
