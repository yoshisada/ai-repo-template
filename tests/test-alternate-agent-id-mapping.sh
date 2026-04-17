#!/usr/bin/env bash
# Test: alternate_agent_id mapping via atomic mkdir lock
# Simulates the post-tool-use.sh activate.sh interception for teammate agents
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

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PARENT_STATE="$TMPDIR/parent_state.json"
WORKER_STATE="$TMPDIR/worker_state.json"
LOCKS_DIR="$TMPDIR/locks"
mkdir -p "$LOCKS_DIR"

WORKFLOW_FILE="$REPO_DIR/workflows/tests/team-static.json"
SUB_WORKFLOW_FILE="$REPO_DIR/workflows/tests/team-sub-worker.json"

echo "=== Test: alternate_agent_id mapping ==="

# Setup parent state with 3 running teammates
WORKFLOW=$(workflow_load "$WORKFLOW_FILE")
state_init "$PARENT_STATE" "$WORKFLOW" "sess-123" "" "$WORKFLOW_FILE"
state_set_team "$PARENT_STATE" "create-team" "test-static-team"

# Add teammates with running status and team-format agent_ids
# (simulating what dispatch_team_wait does after Agent calls with our fix)
for i in 1 2 3; do
  state_add_teammate "$PARENT_STATE" "create-team" "worker-$i" "" "worker-$i@test-static-team" ".wheel/outputs/worker-$i" "{\"id\":$i}"
  state_update_teammate_status "$PARENT_STATE" "create-team" "worker-$i" "running"
done

# Verify parent state has running teammates with agent_ids
state=$(state_read "$PARENT_STATE")
for i in 1 2 3; do
  aid=$(echo "$state" | jq -r ".teams[\"create-team\"].teammates[\"worker-$i\"].agent_id")
  status=$(echo "$state" | jq -r ".teams[\"create-team\"].teammates[\"worker-$i\"].status")
  assert_eq "parent worker-$i agent_id" "worker-$i@test-static-team" "$aid"
  assert_eq "parent worker-$i status" "running" "$status"
done

# Create worker sub-workflow state (simulating activate.sh interception)
SUB_WORKFLOW=$(workflow_load "$SUB_WORKFLOW_FILE")
state_init "$WORKER_STATE" "$SUB_WORKFLOW" "sess-123" "raw-agent-id-abc123" "$SUB_WORKFLOW_FILE"

# Verify worker state has NO alternate_agent_id yet
worker_state=$(state_read "$WORKER_STATE")
alt_aid=$(echo "$worker_state" | jq -r '.alternate_agent_id // "null"')
assert_eq "worker initial alternate_agent_id" "null" "$alt_aid"

# Simulate the mapping logic from post-tool-use.sh
# Find running teammate IDs from parent state
_tids=$(jq -r '
  [.teams // {} | to_entries[] | .value.teammates // {} | to_entries[] |
   select(.value.status == "running") | .value.agent_id // empty] | .[]
' "$PARENT_STATE" 2>/dev/null) || true

# Try to atomically claim one via mkdir lock
claimed_tid=""
while IFS= read -r _tid; do
  [[ -z "$_tid" ]] && continue
  _lock="${LOCKS_DIR}/agent_map_${_tid//[@\/]/_}"
  if mkdir "$_lock" 2>/dev/null; then
    claimed_tid="$_tid"
    _st=$(state_read "$WORKER_STATE")
    state_write "$WORKER_STATE" "$(printf '%s\n' "$_st" | jq --arg alt "$_tid" '.alternate_agent_id = $alt')"
    break
  fi
done <<< "$_tids"

assert_eq "claimed a team-format ID" "true" "$([[ -n "$claimed_tid" ]] && echo true || echo false)"

# Verify worker state now has alternate_agent_id
worker_state=$(state_read "$WORKER_STATE")
alt_aid=$(echo "$worker_state" | jq -r '.alternate_agent_id // "null"')
assert_eq "worker alternate_agent_id is team-format" "true" "$([[ "$alt_aid" == *"@"* ]] && echo true || echo false)"

echo "  (claimed: $claimed_tid)"

# Test resolve_state_file with the team-format ID
# Create a temp .wheel dir with the worker state
WHEEL_DIR="$TMPDIR/wheel"
mkdir -p "$WHEEL_DIR"
cp "$WORKER_STATE" "$WHEEL_DIR/state_raw-agent-id-abc123.json"

# Simulate hook input with team-format agent_id
HOOK_INPUT="{\"session_id\":\"sess-123\",\"agent_id\":\"$claimed_tid\"}"
resolved=$(resolve_state_file "$WHEEL_DIR" "$HOOK_INPUT" 2>/dev/null) || true
assert_eq "resolve_state_file matches via alternate_agent_id" "true" "$([[ -n "$resolved" ]] && echo true || echo false)"

# Test that a second worker claims a different ID
WORKER_STATE2="$TMPDIR/worker_state2.json"
state_init "$WORKER_STATE2" "$SUB_WORKFLOW" "sess-123" "raw-agent-id-def456" "$SUB_WORKFLOW_FILE"

claimed_tid2=""
while IFS= read -r _tid; do
  [[ -z "$_tid" ]] && continue
  _lock="${LOCKS_DIR}/agent_map_${_tid//[@\/]/_}"
  if mkdir "$_lock" 2>/dev/null; then
    claimed_tid2="$_tid"
    _st=$(state_read "$WORKER_STATE2")
    state_write "$WORKER_STATE2" "$(printf '%s\n' "$_st" | jq --arg alt "$_tid" '.alternate_agent_id = $alt')"
    break
  fi
done <<< "$_tids"

assert_eq "second worker claimed different ID" "true" "$([[ -n "$claimed_tid2" && "$claimed_tid2" != "$claimed_tid" ]] && echo true || echo false)"
echo "  (claimed: $claimed_tid2)"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
