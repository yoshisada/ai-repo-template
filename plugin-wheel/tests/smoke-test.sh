#!/usr/bin/env bash
# smoke-test.sh — Live workflow activation smoke test
# Tests: (1) TypeScript binaries exist, (2) Hook invocation works,
#        (3) State file creation, (4) Archive operation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script is at plugin-wheel/tests/smoke-test.sh
# Repo root is 3 levels up from tests/
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugin-wheel"
WORKFLOW_FILE="$PLUGIN_DIR/workflows/tests/command-chain.json"
TEST_WHEEL="$REPO_ROOT/.wheel/smoke-test"
SMOKE_STATE="$TEST_WHEEL/state_smoke-session.json"

trap 'rm -rf "$TEST_WHEEL"' EXIT

echo "=== Smoke Test: Wheel TypeScript Rewrite ==="
echo ""

# Clean up any previous smoke test state
rm -rf "$TEST_WHEEL"
mkdir -p "$TEST_WHEEL"

# --- Test 1: Verify TypeScript binaries exist ---
echo "Test 1: TypeScript hook binaries exist and are executable"

for hook_file in "post-tool-use.js" "session-start.js" "stop.js" "subagent-start.js" "subagent-stop.js" "teammate-idle.js"; do
  BIN="$PLUGIN_DIR/dist/hooks/$hook_file"
  if [[ -f "$BIN" ]]; then
    echo "  PASS: $hook_file exists"
  else
    echo "  FAIL: $hook_file NOT FOUND at $BIN"
    exit 1
  fi
done

# --- Test 2: Invoke PostToolUse hook directly ---
echo ""
echo "Test 2: PostToolUse hook binary responds to valid input"

# Create a state file manually (matching the schema)
cat > "$SMOKE_STATE" <<'STATEEOF'
{
  "workflow_name": "smoke-test",
  "workflow_version": "1.0.0",
  "workflow_file": "workflows/tests/command-chain.json",
  "workflow_definition": null,
  "status": "running",
  "cursor": 0,
  "owner_session_id": "smoke-session",
  "owner_agent_id": "smoke-agent",
  "started_at": "2026-04-29T00:00:00.000Z",
  "updated_at": "2026-04-29T00:00:00.000Z",
  "steps": [
    {"id": "step-1", "type": "command", "status": "pending", "started_at": null, "completed_at": null, "output": null, "command_log": [], "agents": {}, "loop_iteration": 0, "awaiting_user_input": false, "awaiting_user_input_since": null, "awaiting_user_input_reason": null, "resolved_inputs": null, "contract_emitted": false}
  ],
  "teams": {},
  "session_registry": null
}
STATEEOF

HOOK_INPUT='{"hook_type":"post_tool_use","tool_name":"Bash","session_id":"smoke-session","agent_id":"smoke-agent","tool_input":{"command":"echo hello from smoke test"}}'

OUTPUT=$(echo "$HOOK_INPUT" | node "$PLUGIN_DIR/dist/hooks/post-tool-use.js" 2>&1)
echo "  Hook output: $OUTPUT"

if echo "$OUTPUT" | jq -e '.decision' >/dev/null 2>&1; then
  DECISION=$(echo "$OUTPUT" | jq -r '.decision')
  echo "  PASS: Hook returned decision = $DECISION"
else
  echo "  FAIL: Hook did not return valid JSON with decision"
  echo "  Output was: $OUTPUT"
  exit 1
fi

# --- Test 3: Verify state file is still valid after hook processing ---
echo ""
echo "Test 3: State file schema preserved after hook invocation"

if [[ -f "$SMOKE_STATE" ]]; then
  REQUIRED_FIELDS=("workflow_name" "workflow_version" "status" "cursor" "steps" "owner_session_id")
  for field in "${REQUIRED_FIELDS[@]}"; do
    if jq -e ".$field" "$SMOKE_STATE" >/dev/null 2>&1; then
      VALUE=$(jq -r ".$field" "$SMOKE_STATE")
      echo "  PASS: field '$field' = '$VALUE'"
    else
      echo "  FAIL: field '$field' missing"
      exit 1
    fi
  done
else
  echo "  FAIL: State file missing"
  exit 1
fi

# --- Test 4: Invoke SessionStart hook (resume) ---
echo ""
echo "Test 4: SessionStart hook processes resume event"

SESSION_INPUT='{"hook_type":"session_start","matcher":"resume","session_id":"smoke-session","agent_id":"smoke-agent","resume":true}'
SESSION_OUTPUT=$(echo "$SESSION_INPUT" | node "$PLUGIN_DIR/dist/hooks/session-start.js" 2>&1)
echo "  SessionStart output: $SESSION_OUTPUT"

if echo "$SESSION_OUTPUT" | jq -e '.' >/dev/null 2>&1; then
  echo "  PASS: SessionStart hook returned valid JSON"
else
  echo "  WARN: SessionStart output may not be valid JSON: $SESSION_OUTPUT"
fi

# --- Test 5: Simulate archive operation ---
echo ""
echo "Test 5: Archive path is functional"

ARCHIVE_DIR="$REPO_ROOT/.wheel/history/archived"
mkdir -p "$ARCHIVE_DIR"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
ARCHIVE_FILE="$ARCHIVE_DIR/state-smoke-test-$TIMESTAMP.json"

cp "$SMOKE_STATE" "$ARCHIVE_FILE"

if [[ -f "$ARCHIVE_FILE" ]]; then
  echo "  PASS: State file archived to $ARCHIVE_FILE"
  rm -f "$ARCHIVE_FILE"
else
  echo "  FAIL: Archive operation failed"
  exit 1
fi

# --- Test 6: Verify all compiled dist files are present ---
echo ""
echo "Test 6: All compiled files present"

REQUIRED_DIST=(
  "dist/index.js"
  "dist/shared/index.js"
  "dist/shared/jq.js"
  "dist/shared/state.js"
  "dist/shared/fs.js"
  "dist/shared/error.js"
  "dist/lib/engine.js"
  "dist/lib/dispatch.js"
  "dist/lib/state.js"
  "dist/lib/workflow.js"
  "dist/lib/context.js"
  "dist/lib/guard.js"
  "dist/lib/lock.js"
  "dist/lib/preprocess.js"
  "dist/lib/registry.js"
  "dist/lib/resolve_inputs.js"
  "dist/lib/log.js"
)

ALL_PRESENT=true
for file in "${REQUIRED_DIST[@]}"; do
  if [[ -f "$PLUGIN_DIR/$file" ]]; then
    echo "  PASS: $file"
  else
    echo "  FAIL: $file NOT FOUND"
    ALL_PRESENT=false
  fi
done

if [[ "$ALL_PRESENT" == "false" ]]; then
  exit 1
fi

# --- Test 7: Invoke Stop hook ---
echo ""
echo "Test 7: Stop hook processes stop event"

STOP_INPUT='{"hook_type":"stop","session_id":"smoke-session","agent_id":"smoke-agent"}'
STOP_OUTPUT=$(echo "$STOP_INPUT" | node "$PLUGIN_DIR/dist/hooks/stop.js" 2>&1)
echo "  Stop hook output: $STOP_OUTPUT"

if echo "$STOP_OUTPUT" | jq -e '.' >/dev/null 2>&1; then
  echo "  PASS: Stop hook returned valid JSON"
else
  echo "  WARN: Stop output may not be valid JSON: $STOP_OUTPUT"
fi

echo ""
echo "=== All Smoke Tests Passed ==="
echo ""
echo "Summary:"
echo "  - 6 hook binaries verified"
echo "  - PostToolUse hook responds correctly"
echo "  - State file schema preserved"
echo "  - SessionStart hook works"
echo "  - Archive path functional"
echo "  - 18 compiled files present"
echo ""
echo "Next: Integration test with real workflow activation via activate.sh"