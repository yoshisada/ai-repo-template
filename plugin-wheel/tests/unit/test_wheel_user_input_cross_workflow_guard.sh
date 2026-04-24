#!/usr/bin/env bash
# FR-010 (wheel-user-input): Cross-workflow guard — only one workflow may be
# awaiting user input at a time. Scans all .wheel/state_*.json files
# excluding the resolved current one.
#
# Covers US6.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI="${PLUGIN_DIR}/bin/wheel-flag-needs-input"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

scratch="$(mktemp -d -t wheel-guard.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
mkdir -p .wheel workflows

# Blocking workflow: already awaiting user input on its current step.
blocker_wf="${scratch}/workflows/blocker.json"
jq -n '{
  name: "blocker", version: "1",
  steps: [{id: "block-step", type: "agent", output: "b.json", instruction: "i", allow_user_input: true}]
}' > "$blocker_wf"
blocker_state="${scratch}/.wheel/state_AAA_blocker.json"
# Note: use parent_workflow=""; no chain. Make this one NOT the leaf by setting
# status=running but a second candidate refers to it. Easier: set blocker's
# status=completed so resolve_active_state_file_nohook skips it (we want blocker
# to hold the flag but NOT be the resolved active workflow).
jq -n --arg wf "$blocker_wf" '{
  workflow_name: "blocker", workflow_version: "1", workflow_file: $wf,
  status: "completed", cursor: 0,
  owner_session_id: "sid1", owner_agent_id: "aid1",
  started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
  steps: [{id: "block-step", type: "agent", status: "working",
           awaiting_user_input: true,
           awaiting_user_input_since: "2026-04-24T00:00:00Z",
           awaiting_user_input_reason: "blocking the whole show"}]
}' > "$blocker_state"

# Active workflow (the one the CLI will resolve): running, permits input.
active_wf="${scratch}/workflows/active.json"
jq -n '{
  name: "active", version: "1",
  steps: [{id: "ask-step", type: "agent", output: "a.json", instruction: "i", allow_user_input: true}]
}' > "$active_wf"
active_state="${scratch}/.wheel/state_BBB_active.json"
jq -n --arg wf "$active_wf" '{
  workflow_name: "active", workflow_version: "1", workflow_file: $wf,
  status: "running", cursor: 0,
  owner_session_id: "sid2", owner_agent_id: "aid2",
  started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
  steps: [{id: "ask-step", type: "agent", status: "working"}]
}' > "$active_state"

# --- Case 1: guard fires — exits 1, names blocking workflow ---
# But wait — the blocker is status=completed, so resolve_active_state_file_nohook
# returns only the active state. The guard scan at step 5 iterates ALL state
# files regardless of status (per FR-010 / contracts §5.3 step 5), so it still
# sees the blocker's awaiting flag. Confirm:
out=$("$CLI" "want to ask" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ "$out" == *"another workflow is waiting on user input"* ]] && [[ "$out" == *"blocker"* ]] && [[ "$out" == *"block-step"* ]]; then
  assert_pass "guard exits 1 and names blocking workflow + step in stderr"
else
  assert_fail "guard expected rc=1, blocker+block-step in stderr — got rc=$rc out=$out"
fi

# State on the active file should be unchanged.
awaiting_after=$(jq -r '.steps[0].awaiting_user_input // false' "$active_state")
if [[ "$awaiting_after" == "false" ]]; then
  assert_pass "guard denial leaves active state untouched"
else
  assert_fail "guard allowed set: awaiting=$awaiting_after"
fi

# --- Case 2: clear the blocker's flag → guard passes ---
jq '.steps[0].awaiting_user_input = false
    | .steps[0].awaiting_user_input_since = null
    | .steps[0].awaiting_user_input_reason = null' "$blocker_state" > "${blocker_state}.tmp"
mv "${blocker_state}.tmp" "$blocker_state"

out=$("$CLI" "now it is my turn" 2>&1) && rc=0 || rc=$?
awaiting_after=$(jq -r '.steps[0].awaiting_user_input // false' "$active_state")
if [[ "$rc" -eq 0 ]] && [[ "$awaiting_after" == "true" ]]; then
  assert_pass "guard passes when no other workflow is awaiting"
else
  assert_fail "after clear: rc=$rc awaiting=$awaiting_after out=$out"
fi

# --- Case 3: guard scan excludes the resolved (current) state file ---
# The active state now has awaiting=true (from case 2). Calling again should
# NOT trip the guard on its own file — it should pass (and idempotently
# re-set). Reset active awaiting first.
jq '.steps[0].awaiting_user_input = false
    | .steps[0].awaiting_user_input_since = null
    | .steps[0].awaiting_user_input_reason = null' "$active_state" > "${active_state}.tmp"
mv "${active_state}.tmp" "$active_state"
# Simulate active being its own awaiter by re-setting directly, then invoking CLI.
jq '.steps[0].awaiting_user_input = true
    | .steps[0].awaiting_user_input_since = "2026-04-24T00:00:00Z"
    | .steps[0].awaiting_user_input_reason = "previous"' "$active_state" > "${active_state}.tmp"
mv "${active_state}.tmp" "$active_state"

out=$("$CLI" "re-ask" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  new_reason=$(jq -r '.steps[0].awaiting_user_input_reason' "$active_state")
  if [[ "$new_reason" == "re-ask" ]]; then
    assert_pass "guard excludes the current (resolved) state file"
  else
    assert_fail "self-exclusion: reason not updated to 're-ask' — got $new_reason"
  fi
else
  assert_fail "guard false-positive on own state: rc=$rc out=$out"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
