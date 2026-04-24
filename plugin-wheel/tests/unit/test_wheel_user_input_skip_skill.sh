#!/usr/bin/env bash
# FR-011 (wheel-user-input): /wheel:wheel-skip — exercise the three documented
# branches of the skip logic (active flag set, no flag, no workflow). Tests
# invoke the bin/wheel-skip CLI which is what the skill body calls.
#
# Covers US4.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKIP_BIN="${PLUGIN_DIR}/bin/wheel-skip"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

scratch="$(mktemp -d -t wheel-skip.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
mkdir -p .wheel workflows

# --- Case 1: flag set → sentinel written + flag cleared ---
wf="${scratch}/workflows/w1.json"
jq -n '{name: "w1", version: "1", steps: [{id: "ask-step", type: "agent", output: ".wheel/outputs/ask-step.json", allow_user_input: true}]}' > "$wf"
state="${scratch}/.wheel/state_a1.json"
jq -n --arg wf "$wf" '{
  workflow_name: "w1", workflow_version: "1", workflow_file: $wf,
  status: "running", cursor: 0,
  owner_session_id: "sid", owner_agent_id: "aid",
  started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
  steps: [{id: "ask-step", type: "agent", status: "working",
           awaiting_user_input: true,
           awaiting_user_input_since: "2026-04-24T00:00:00Z",
           awaiting_user_input_reason: "need answer"}]
}' > "$state"

out=$("$SKIP_BIN" 2>&1) && rc=0 || rc=$?
sentinel=".wheel/outputs/ask-step.json"
if [[ "$rc" -eq 0 ]] && [[ -f "$sentinel" ]]; then
  cancelled=$(jq -r '.cancelled' "$sentinel" 2>/dev/null)
  reason=$(jq -r '.reason' "$sentinel" 2>/dev/null)
  if [[ "$cancelled" == "true" ]] && [[ "$reason" == "user-skipped" ]]; then
    assert_pass "sentinel written with correct shape"
  else
    assert_fail "sentinel shape wrong: cancelled=$cancelled reason=$reason"
  fi
else
  assert_fail "skip bin failed: rc=$rc out=$out sentinel_exists=[[ -f $sentinel ]]"
fi

awaiting_after=$(jq -r '.steps[0].awaiting_user_input' "$state")
since_after=$(jq -r '.steps[0].awaiting_user_input_since' "$state")
reason_after=$(jq -r '.steps[0].awaiting_user_input_reason' "$state")
if [[ "$awaiting_after" == "false" ]] && [[ "$since_after" == "null" ]] && [[ "$reason_after" == "null" ]]; then
  assert_pass "flag cleared on state file"
else
  assert_fail "flag not cleared: awaiting=$awaiting_after since=$since_after reason=$reason_after"
fi

if [[ "$out" == *"skipped step 'ask-step'"* ]]; then
  assert_pass "confirmation message names the step"
else
  assert_fail "confirmation message: $out"
fi

# --- Case 2: no flag set → friendly message + exit 0 + state unchanged ---
rm -rf .wheel
mkdir -p .wheel workflows
jq -n '{name: "w2", version: "1", steps: [{id: "s", type: "agent", output: "o.json"}]}' > "${scratch}/workflows/w2.json"
state2="${scratch}/.wheel/state_a2.json"
jq -n --arg wf "${scratch}/workflows/w2.json" '{
  workflow_name: "w2", workflow_version: "1", workflow_file: $wf,
  status: "running", cursor: 0,
  owner_session_id: "sid", owner_agent_id: "aid",
  started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
  steps: [{id: "s", type: "agent", status: "working"}]
}' > "$state2"
before_sha=$(shasum "$state2" | awk '{print $1}')
out=$("$SKIP_BIN" 2>&1) && rc=0 || rc=$?
after_sha=$(shasum "$state2" | awk '{print $1}')
if [[ "$rc" -eq 0 ]] && [[ "$out" == *"no interactive step to skip"* ]] && [[ "$before_sha" == "$after_sha" ]]; then
  assert_pass "no flag set → friendly exit 0, state unchanged"
else
  assert_fail "no flag case: rc=$rc out=$out sha_match=[$before_sha==$after_sha]"
fi

# --- Case 3: no active workflow → friendly message + exit 0 ---
rm -rf .wheel
mkdir -p .wheel
out=$("$SKIP_BIN" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ "$out" == *"no interactive step to skip"* ]]; then
  assert_pass "no active workflow → friendly exit 0"
else
  assert_fail "no workflow case: rc=$rc out=$out"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
