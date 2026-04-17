#!/usr/bin/env bash
# Test: agent step with no output auto-completes when chained via PostToolUse
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

echo "=== Test: PostToolUse chains through no-output agent steps ==="

# Use a non-terminal workflow to isolate the no-output chain behavior
# Create a temp workflow without terminal flag
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR; rm -f .wheel/outputs/worker-result-test.md" EXIT

cat > "$TMPDIR/workflow.json" << 'EOF'
{
  "name": "test-chain",
  "steps": [
    {"id": "step-a", "type": "command", "command": "echo done", "output": ".wheel/outputs/a.txt"},
    {"id": "step-b", "type": "agent", "instruction": "Do work", "output": ".wheel/outputs/worker-result-test.md"},
    {"id": "step-c", "type": "agent", "instruction": "Report back (no output)"},
    {"id": "step-d", "type": "command", "command": "echo final"}
  ]
}
EOF

STATE_FILE="$TMPDIR/state.json"
WORKFLOW_FILE="$TMPDIR/workflow.json"

WORKFLOW=$(workflow_load "$WORKFLOW_FILE")
state_init "$STATE_FILE" "$WORKFLOW" "sess-123" "agent-abc" "$WORKFLOW_FILE"

# Simulate: step-a done, step-b working at cursor 1
state_set_step_status "$STATE_FILE" 0 "done"
state_set_step_status "$STATE_FILE" 1 "working"
state_set_cursor "$STATE_FILE" 1

# Create output file for step-b
mkdir -p .wheel/outputs
echo "test result" > .wheel/outputs/worker-result-test.md

# Init engine
engine_init "$WORKFLOW_FILE" "$STATE_FILE"

# Simulate PostToolUse for Write tool targeting step-b output
MOCK_HOOK_INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$(pwd)/.wheel/outputs/worker-result-test.md\"},\"session_id\":\"sess-123\",\"agent_id\":\"agent-abc\"}"
result=$(engine_handle_hook "post_tool_use" "$MOCK_HOOK_INPUT" 2>/dev/null)

# Check: step-b done, step-c (no output) auto-completed, cursor at step-d
state=$(state_read "$STATE_FILE")
stepb_status=$(echo "$state" | jq -r '.steps[1].status')
stepc_status=$(echo "$state" | jq -r '.steps[2].status')
cursor=$(echo "$state" | jq -r '.cursor')

assert_eq "step-b done" "done" "$stepb_status"
assert_eq "step-c auto-completed" "done" "$stepc_status"
assert_eq "cursor past step-d (workflow complete)" "4" "$cursor"

# step-d (command) should have been auto-executed too
stepd_status=$(echo "$state" | jq -r '.steps[3].status')
assert_eq "step-d executed" "done" "$stepd_status"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
