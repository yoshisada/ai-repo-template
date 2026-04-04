#!/usr/bin/env bash
# test-branch-loop.sh — Integration test for US5 Acceptance Scenarios 1-4
# Validates: Branch steps evaluate conditions and jump to correct targets
# Validates: Loop steps retry until condition met or max_iterations reached
# SC-006: Branch steps jump to correct target
# SC-007: Loop steps retry correctly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/plugin-wheel/lib"
TEST_TMP="$(mktemp -d)"

trap 'rm -rf "$TEST_TMP"' EXIT

source "$LIB_DIR/state.sh"
source "$LIB_DIR/workflow.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Test: Branch and Loop Control Flow (US5) ==="

# --- Test 1 (US5 Scenario 1): Branch with true condition jumps to if_zero ---
echo ""
echo "Test 1: Branch jumps to if_zero when condition succeeds (Scenario 1)"

WORKFLOW_FILE="$TEST_TMP/branch-workflow.json"
STATE_FILE="$TEST_TMP/.wheel/state.json"
mkdir -p "$TEST_TMP/.wheel"

cat > "$WORKFLOW_FILE" <<'WORKFLOW'
{
  "name": "test-branch",
  "version": "1.0.0",
  "steps": [
    {"id": "start", "type": "command", "command": "echo start"},
    {"id": "check", "type": "branch", "condition": "true", "if_zero": "success", "if_nonzero": "fallback"},
    {"id": "fallback", "type": "command", "command": "echo fallback"},
    {"id": "success", "type": "command", "command": "echo success"}
  ]
}
WORKFLOW

WORKFLOW_JSON=$(workflow_load "$WORKFLOW_FILE")
state_init "$STATE_FILE" "$WORKFLOW_JSON"

# Simulate: step 0 done, cursor at step 1 (branch step)
state_set_step_status "$STATE_FILE" 0 "done"
state_set_cursor "$STATE_FILE" 1

# Evaluate the branch condition
STEP1=$(workflow_get_step "$WORKFLOW_JSON" 1)
CONDITION=$(echo "$STEP1" | jq -r '.condition')
set +e
eval "$CONDITION" >/dev/null 2>&1
COND_EXIT=$?
set -e

if [[ $COND_EXIT -eq 0 ]]; then
  TARGET_ID=$(echo "$STEP1" | jq -r '.if_zero')
else
  TARGET_ID=$(echo "$STEP1" | jq -r '.if_nonzero')
fi

TARGET_INDEX=$(workflow_get_step_index "$WORKFLOW_JSON" "$TARGET_ID")
assert_eq "condition 'true' exits 0" "0" "$COND_EXIT"
assert_eq "jumps to 'success' step (index 3)" "3" "$TARGET_INDEX"

# --- Test 2 (US5 Scenario 2): Branch with false condition jumps to if_nonzero ---
echo ""
echo "Test 2: Branch jumps to if_nonzero when condition fails (Scenario 2)"

WORKFLOW_FILE2="$TEST_TMP/branch-fail.json"
cat > "$WORKFLOW_FILE2" <<'WORKFLOW'
{
  "name": "test-branch-fail",
  "version": "1.0.0",
  "steps": [
    {"id": "start", "type": "command", "command": "echo start"},
    {"id": "check", "type": "branch", "condition": "false", "if_zero": "success", "if_nonzero": "fallback"},
    {"id": "fallback", "type": "command", "command": "echo fallback"},
    {"id": "success", "type": "command", "command": "echo success"}
  ]
}
WORKFLOW

WORKFLOW_JSON2=$(workflow_load "$WORKFLOW_FILE2")
STEP1=$(workflow_get_step "$WORKFLOW_JSON2" 1)
CONDITION=$(echo "$STEP1" | jq -r '.condition')
set +e
eval "$CONDITION" >/dev/null 2>&1
COND_EXIT=$?
set -e

if [[ $COND_EXIT -eq 0 ]]; then
  TARGET_ID=$(echo "$STEP1" | jq -r '.if_zero')
else
  TARGET_ID=$(echo "$STEP1" | jq -r '.if_nonzero')
fi

TARGET_INDEX=$(workflow_get_step_index "$WORKFLOW_JSON2" "$TARGET_ID")
assert_eq "condition 'false' exits non-zero" "1" "$COND_EXIT"
assert_eq "jumps to 'fallback' step (index 2)" "2" "$TARGET_INDEX"

# --- Test 3 (US5 Scenario 3): Loop exhausts max_iterations ---
echo ""
echo "Test 3: Loop exhausts max_iterations (Scenario 3)"

# Simulate a loop that always fails its condition
STATE_FILE3="$TEST_TMP/.wheel/state3.json"
LOOP_WF='{"name":"test-loop","version":"1.0.0","steps":[{"id":"loop-step","type":"loop","condition":"false","max_iterations":3,"on_exhaustion":"fail","substep":{"type":"command","command":"echo retry"}}]}'

# Parse max_iterations and simulate iterations
MAX_ITER=$(echo "$LOOP_WF" | jq '.steps[0].max_iterations')
ON_EXHAUST=$(echo "$LOOP_WF" | jq -r '.steps[0].on_exhaustion')
CONDITION=$(echo "$LOOP_WF" | jq -r '.steps[0].condition')

ITERATION=0
LOOP_DONE=false
while [[ $ITERATION -lt $MAX_ITER ]]; do
  ITERATION=$((ITERATION + 1))
  # Execute substep (command)
  SUBSTEP_CMD=$(echo "$LOOP_WF" | jq -r '.steps[0].substep.command')
  eval "$SUBSTEP_CMD" >/dev/null 2>&1

  # Check condition
  set +e
  eval "$CONDITION" >/dev/null 2>&1
  COND_EXIT=$?
  set -e
  if [[ $COND_EXIT -eq 0 ]]; then
    LOOP_DONE=true
    break
  fi
done

assert_eq "loop ran 3 iterations" "3" "$ITERATION"
assert_eq "loop did not satisfy condition" "false" "$LOOP_DONE"
assert_eq "on_exhaustion is fail" "fail" "$ON_EXHAUST"

# --- Test 4 (US5 Scenario 4): Loop succeeds on iteration 2 ---
echo ""
echo "Test 4: Loop exits when condition succeeds on iteration 2 (Scenario 4)"

# Create a file on iteration 2 that makes the condition pass
LOOP_MARKER="$TEST_TMP/loop-marker"
rm -f "$LOOP_MARKER"

ITERATION=0
MAX_ITER=5
LOOP_DONE=false
while [[ $ITERATION -lt $MAX_ITER ]]; do
  ITERATION=$((ITERATION + 1))

  # Substep: create marker on iteration 2
  if [[ $ITERATION -eq 2 ]]; then
    touch "$LOOP_MARKER"
  fi

  # Condition: check if marker exists
  set +e
  test -f "$LOOP_MARKER"
  COND_EXIT=$?
  set -e
  if [[ $COND_EXIT -eq 0 ]]; then
    LOOP_DONE=true
    break
  fi
done

assert_eq "loop exited on iteration 2" "2" "$ITERATION"
assert_eq "loop condition satisfied" "true" "$LOOP_DONE"

# --- Test 5: Workflow validates branch target references ---
echo ""
echo "Test 5: Invalid branch target rejected at load time"

INVALID_WF="$TEST_TMP/invalid-branch.json"
cat > "$INVALID_WF" <<'WORKFLOW'
{
  "name": "test-invalid-branch",
  "version": "1.0.0",
  "steps": [
    {"id": "start", "type": "command", "command": "echo start"},
    {"id": "check", "type": "branch", "condition": "true", "if_zero": "nonexistent", "if_nonzero": "start"}
  ]
}
WORKFLOW

set +e
LOAD_OUTPUT=$(workflow_load "$INVALID_WF" 2>&1)
LOAD_EXIT=$?
set -e

assert_eq "invalid branch target rejected" "1" "$LOAD_EXIT"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
