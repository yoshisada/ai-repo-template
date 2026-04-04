#!/usr/bin/env bash
# test-command-step.sh — Integration test for US1 Scenario 4
# Validates: Command steps execute, record output/exit_code/timestamp in state.json
# SC-005: Command step output appears in state.json with exit code and timestamp
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

echo "=== Test: Command Steps (US1 Scenario 4) ==="

# --- Setup ---
WORKFLOW_FILE="$TEST_TMP/workflow.json"
STATE_FILE="$TEST_TMP/.wheel/state.json"
mkdir -p "$TEST_TMP/.wheel"

cat > "$WORKFLOW_FILE" <<'WORKFLOW'
{
  "name": "test-command",
  "version": "1.0.0",
  "steps": [
    {"id": "cmd-1", "type": "command", "command": "echo hello-world"},
    {"id": "cmd-2", "type": "command", "command": "echo step-two-output"},
    {"id": "cmd-fail", "type": "command", "command": "false"}
  ]
}
WORKFLOW

WORKFLOW_JSON=$(workflow_load "$WORKFLOW_FILE")

# --- Test 1: Command step records output ---
echo ""
echo "Test 1: Command step records output and exit code"

state_init "$STATE_FILE" "$WORKFLOW_JSON"

# Simulate engine executing command step 0
state_set_step_status "$STATE_FILE" 0 "working"

# Execute the command (simulating what dispatch_command would do)
STEP0=$(workflow_get_step "$WORKFLOW_JSON" 0)
CMD=$(echo "$STEP0" | jq -r '.command')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

CMD_OUTPUT=$(eval "$CMD" 2>&1) || true
CMD_EXIT=$?

# Record in command log
state_append_command_log "$STATE_FILE" 0 "$CMD" "$CMD_EXIT" "$TIMESTAMP"
state_set_step_output "$STATE_FILE" 0 "$CMD_OUTPUT"
state_set_step_status "$STATE_FILE" 0 "done"

STATE=$(state_read "$STATE_FILE")
assert_eq "step 0 is done" "done" "$(state_get_step_status "$STATE" 0)"
assert_eq "step 0 output is hello-world" "hello-world" "$(state_get_step_output "$STATE" 0)"

CMD_LOG=$(state_get_command_log "$STATE" 0)
LOG_CMD=$(echo "$CMD_LOG" | jq -r '.[0].command')
LOG_EXIT=$(echo "$CMD_LOG" | jq '.[0].exit_code')
assert_eq "command log records command" "echo hello-world" "$LOG_CMD"
assert_eq "command log records exit 0" "0" "$LOG_EXIT"

# --- Test 2: Multiple command steps chain ---
echo ""
echo "Test 2: Sequential command steps advance correctly"

state_set_cursor "$STATE_FILE" 1
state_set_step_status "$STATE_FILE" 1 "working"

STEP1=$(workflow_get_step "$WORKFLOW_JSON" 1)
CMD=$(echo "$STEP1" | jq -r '.command')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
CMD_OUTPUT=$(eval "$CMD" 2>&1) || true
CMD_EXIT=$?

state_append_command_log "$STATE_FILE" 1 "$CMD" "$CMD_EXIT" "$TIMESTAMP"
state_set_step_output "$STATE_FILE" 1 "$CMD_OUTPUT"
state_set_step_status "$STATE_FILE" 1 "done"
state_set_cursor "$STATE_FILE" 2

STATE=$(state_read "$STATE_FILE")
assert_eq "step 1 output is step-two-output" "step-two-output" "$(state_get_step_output "$STATE" 1)"
assert_eq "cursor at step 2" "2" "$(state_get_cursor "$STATE")"

# --- Test 3: Failed command step records non-zero exit ---
echo ""
echo "Test 3: Failed command records non-zero exit code"

state_set_step_status "$STATE_FILE" 2 "working"

STEP2=$(workflow_get_step "$WORKFLOW_JSON" 2)
CMD=$(echo "$STEP2" | jq -r '.command')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
CMD_OUTPUT=$(eval "$CMD" 2>&1) || true
CMD_EXIT=$?
# 'false' exits with 1 — but since we do || true above, we need to capture differently
# Re-run to get actual exit code
set +e
eval "$CMD" >/dev/null 2>&1
CMD_EXIT=$?
set -e

state_append_command_log "$STATE_FILE" 2 "$CMD" "$CMD_EXIT" "$TIMESTAMP"
state_set_step_status "$STATE_FILE" 2 "failed"

STATE=$(state_read "$STATE_FILE")
assert_eq "step 2 is failed" "failed" "$(state_get_step_status "$STATE" 2)"

CMD_LOG=$(state_get_command_log "$STATE" 2)
LOG_EXIT=$(echo "$CMD_LOG" | jq '.[0].exit_code')
assert_eq "failed command exit code is 1" "1" "$LOG_EXIT"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
