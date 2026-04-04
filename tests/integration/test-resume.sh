#!/usr/bin/env bash
# test-resume.sh — Integration test for US2 Acceptance Scenarios 1-2
# Validates: A crashed session resumes from the last completed step
# SC-002: Resume from correct step within 2 seconds
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

echo "=== Test: Resume Workflow (US2) ==="

# --- Setup ---
WORKFLOW_FILE="$TEST_TMP/workflow.json"
STATE_FILE="$TEST_TMP/.wheel/state.json"
mkdir -p "$TEST_TMP/.wheel"

cat > "$WORKFLOW_FILE" <<'WORKFLOW'
{
  "name": "test-resume",
  "version": "1.0.0",
  "steps": [
    {"id": "step-1", "type": "command", "command": "echo hello"},
    {"id": "step-2", "type": "agent", "instruction": "Do step 2"},
    {"id": "step-3", "type": "command", "command": "echo done"}
  ]
}
WORKFLOW

WORKFLOW_JSON=$(workflow_load "$WORKFLOW_FILE")

# --- Test 1 (US2 Scenario 1): Resume from step 3 when steps 1-2 are done ---
echo ""
echo "Test 1: Resume at step 3 when steps 1-2 done (Scenario 1)"

state_init "$STATE_FILE" "$WORKFLOW_JSON"

# Simulate: steps 1-2 completed, step 3 pending
state_set_step_status "$STATE_FILE" 0 "done"
state_set_step_status "$STATE_FILE" 1 "done"
state_set_cursor "$STATE_FILE" 2

# "Crash" — session ends, new session reads state.json
START_TIME=$(date +%s)
STATE=$(state_read "$STATE_FILE")
CURSOR=$(state_get_cursor "$STATE")
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

assert_eq "cursor is at step 2 (0-indexed)" "2" "$CURSOR"
S1=$(state_get_step_status "$STATE" 0)
S2=$(state_get_step_status "$STATE" 1)
S3=$(state_get_step_status "$STATE" 2)
assert_eq "step 0 is done" "done" "$S1"
assert_eq "step 1 is done" "done" "$S2"
assert_eq "step 2 is pending" "pending" "$S3"

# SC-002: Resume within 2 seconds
if [[ $ELAPSED -le 2 ]]; then
  echo "  PASS: resume latency <= 2s (${ELAPSED}s)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: resume latency > 2s (${ELAPSED}s)"
  FAIL=$((FAIL + 1))
fi

# --- Test 2 (US2 Scenario 2): Resume a partially-complete step ---
echo ""
echo "Test 2: Resume a working step with command log context (Scenario 2)"

state_init "$STATE_FILE" "$WORKFLOW_JSON"

# Simulate: step 1 done, step 2 was working when crash happened
state_set_step_status "$STATE_FILE" 0 "done"
state_set_cursor "$STATE_FILE" 1
state_set_step_status "$STATE_FILE" 1 "working"

# Add some command log entries to the working step
state_append_command_log "$STATE_FILE" 1 "git status" 0 "2026-04-03T12:00:00.000Z"
state_append_command_log "$STATE_FILE" 1 "npm test" 1 "2026-04-03T12:00:01.000Z"

# "Crash" and resume — verify command log is available
STATE=$(state_read "$STATE_FILE")
CURSOR=$(state_get_cursor "$STATE")
S2_STATUS=$(state_get_step_status "$STATE" 1)
assert_eq "cursor still at step 1" "1" "$CURSOR"
assert_eq "step 1 still shows working" "working" "$S2_STATUS"

# Command log should be available for context
CMD_LOG=$(state_get_command_log "$STATE" 1)
CMD_COUNT=$(echo "$CMD_LOG" | jq 'length')
assert_eq "command log has 2 entries" "2" "$CMD_COUNT"

FIRST_CMD=$(echo "$CMD_LOG" | jq -r '.[0].command')
FIRST_EXIT=$(echo "$CMD_LOG" | jq '.[0].exit_code')
assert_eq "first command is git status" "git status" "$FIRST_CMD"
assert_eq "first command exit code is 0" "0" "$FIRST_EXIT"

SECOND_CMD=$(echo "$CMD_LOG" | jq -r '.[1].command')
SECOND_EXIT=$(echo "$CMD_LOG" | jq '.[1].exit_code')
assert_eq "second command is npm test" "npm test" "$SECOND_CMD"
assert_eq "second command exit code is 1" "1" "$SECOND_EXIT"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
