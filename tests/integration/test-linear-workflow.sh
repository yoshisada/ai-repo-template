#!/usr/bin/env bash
# test-linear-workflow.sh — Integration test for US1 Acceptance Scenarios 1-3
# Validates: A 3-step workflow completes with state.json showing all steps done in order
# SC-001: Zero LLM routing decisions — engine advances deterministically
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/plugin-wheel/lib"
TEST_TMP="$(mktemp -d)"

trap 'rm -rf "$TEST_TMP"' EXIT

# Source lib modules
source "$LIB_DIR/state.sh"
source "$LIB_DIR/workflow.sh"
source "$LIB_DIR/lock.sh"

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

echo "=== Test: Linear Workflow (US1) ==="

# --- Setup: Create a 3-step workflow ---
WORKFLOW_FILE="$TEST_TMP/workflow.json"
STATE_FILE="$TEST_TMP/.wheel/state.json"
mkdir -p "$TEST_TMP/.wheel"

cat > "$WORKFLOW_FILE" <<'WORKFLOW'
{
  "name": "test-linear",
  "version": "1.0.0",
  "steps": [
    {"id": "step-1", "type": "agent", "instruction": "Do step 1"},
    {"id": "step-2", "type": "agent", "instruction": "Do step 2"},
    {"id": "step-3", "type": "agent", "instruction": "Do step 3"}
  ]
}
WORKFLOW

# --- Test 1: Load workflow ---
echo ""
echo "Test 1: Workflow loads and validates"
WORKFLOW_JSON=$(workflow_load "$WORKFLOW_FILE")
STEP_COUNT=$(workflow_step_count "$WORKFLOW_JSON")
assert_eq "workflow has 3 steps" "3" "$STEP_COUNT"

STEP1=$(workflow_get_step "$WORKFLOW_JSON" 0)
STEP1_ID=$(echo "$STEP1" | jq -r '.id')
assert_eq "step 0 is step-1" "step-1" "$STEP1_ID"

# --- Test 2: Initialize state ---
echo ""
echo "Test 2: State initializes from workflow"
state_init "$STATE_FILE" "$WORKFLOW_JSON"
STATE=$(state_read "$STATE_FILE")

CURSOR=$(state_get_cursor "$STATE")
assert_eq "initial cursor is 0" "0" "$CURSOR"

STATUS=$(echo "$STATE" | jq -r '.status')
assert_eq "workflow status is running" "running" "$STATUS"

S1_STATUS=$(state_get_step_status "$STATE" 0)
S2_STATUS=$(state_get_step_status "$STATE" 1)
S3_STATUS=$(state_get_step_status "$STATE" 2)
assert_eq "step 0 starts pending" "pending" "$S1_STATUS"
assert_eq "step 1 starts pending" "pending" "$S2_STATUS"
assert_eq "step 2 starts pending" "pending" "$S3_STATUS"

# --- Test 3: Simulate step 1 execution (US1 Scenario 1) ---
echo ""
echo "Test 3: Step 1 starts as working (Scenario 1)"
state_set_step_status "$STATE_FILE" 0 "working"
STATE=$(state_read "$STATE_FILE")
S1_STATUS=$(state_get_step_status "$STATE" 0)
assert_eq "step 0 is working" "working" "$S1_STATUS"

# --- Test 4: Step 1 completes, advance to step 2 (US1 Scenario 2) ---
echo ""
echo "Test 4: Step 1 completes, cursor advances (Scenario 2)"
state_set_step_status "$STATE_FILE" 0 "done"
state_set_cursor "$STATE_FILE" 1
STATE=$(state_read "$STATE_FILE")
CURSOR=$(state_get_cursor "$STATE")
S1_STATUS=$(state_get_step_status "$STATE" 0)
assert_eq "step 0 is done" "done" "$S1_STATUS"
assert_eq "cursor advanced to 1" "1" "$CURSOR"

# --- Test 5: Complete steps 2 and 3 (US1 Scenario 3) ---
echo ""
echo "Test 5: All steps complete (Scenario 3)"
state_set_step_status "$STATE_FILE" 1 "working"
state_set_step_status "$STATE_FILE" 1 "done"
state_set_cursor "$STATE_FILE" 2

state_set_step_status "$STATE_FILE" 2 "working"
state_set_step_status "$STATE_FILE" 2 "done"
state_set_cursor "$STATE_FILE" 3

STATE=$(state_read "$STATE_FILE")
CURSOR=$(state_get_cursor "$STATE")
assert_eq "cursor is past last step (3)" "3" "$CURSOR"

S1=$(state_get_step_status "$STATE" 0)
S2=$(state_get_step_status "$STATE" 1)
S3=$(state_get_step_status "$STATE" 2)
assert_eq "step 0 is done" "done" "$S1"
assert_eq "step 1 is done" "done" "$S2"
assert_eq "step 2 is done" "done" "$S3"

# --- Test 6: Step output capture ---
echo ""
echo "Test 6: Step output recorded"
state_set_step_output "$STATE_FILE" 0 "output-from-step-1.txt"
STATE=$(state_read "$STATE_FILE")
OUTPUT=$(state_get_step_output "$STATE" 0)
assert_eq "step 0 output recorded" "output-from-step-1.txt" "$OUTPUT"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
