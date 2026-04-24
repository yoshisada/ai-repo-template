#!/usr/bin/env bash
# FR-005/FR-006/FR-006a/FR-013 (wheel-user-input): CLI exit branches for
# wheel-flag-needs-input. One assertion per exit branch in contracts §5.2.
#
# Covers US1 (happy), US3 (permission), US5 (non-interactive), US6 (guard
# partial — full guard has its own test).
# SC-003: state-file sha unchanged on denial branches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI="${PLUGIN_DIR}/bin/wheel-flag-needs-input"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- Scaffold a scratch workspace ---
scratch="$(mktemp -d -t wheel-cli.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
mkdir -p .wheel workflows

# Helper to build a workflow + state pair.
seed() {
  local wf_name="$1"
  local allow="$2"   # "true" or "false"
  local wf_file="${scratch}/workflows/${wf_name}.json"
  jq -n --arg allow "$allow" '{
    name: $ENV.wf_name, version: "1",
    steps: [{id: "s0", type: "agent", output: "out.json", instruction: "i", allow_user_input: ($allow == "true")}]
  }' > "$wf_file"
  local state_file="${scratch}/.wheel/state_${wf_name}.json"
  jq -n --arg wf "$wf_file" --arg name "$wf_name" '{
    workflow_name: $name, workflow_version: "1", workflow_file: $wf,
    status: "running", cursor: 0,
    owner_session_id: "sid", owner_agent_id: "aid",
    started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
    steps: [{id: "s0", type: "agent", status: "working"}]
  }' > "$state_file"
  echo "$state_file"
}

reset_scratch() {
  rm -f "${scratch}/.wheel"/state_*.json "${scratch}/workflows"/*.json
}

# --- Case 1: missing argument → exit 1 usage ---
if out=$("$CLI" 2>&1); then
  assert_fail "missing arg should exit 1 (got exit 0, output: $out)"
else
  if [[ "$out" == *"usage:"* ]]; then
    assert_pass "missing argument exits 1 with usage"
  else
    assert_fail "missing argument: stderr missing 'usage:' (got: $out)"
  fi
fi

# --- Case 2: no active workflow → exit 1 ---
reset_scratch
WF_NAME="" out=$("$CLI" "some reason" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ "$out" == *"no active workflow"* ]]; then
  assert_pass "no active workflow exits 1 with 'no active workflow'"
else
  assert_fail "no active workflow: rc=$rc out=$out"
fi

# --- Case 3: success — step permits input, no other active workflow ---
reset_scratch
sf=$(wf_name=good seed "good" "true")
out=$("$CLI" "need user info" 2>&1) && rc=0 || rc=$?
awaiting=$(jq -r '.steps[0].awaiting_user_input' "$sf")
reason=$(jq -r '.steps[0].awaiting_user_input_reason' "$sf")
if [[ "$rc" -eq 0 ]] && [[ "$awaiting" == "true" ]] && [[ "$reason" == "need user info" ]] && [[ "$out" == *"awaiting user input on step 's0'"* ]]; then
  assert_pass "happy path sets flag and prints confirmation"
else
  assert_fail "happy path: rc=$rc awaiting=$awaiting reason=$reason out=$out"
fi

# --- Case 4: permission denied (allow_user_input: false) — state byte-unchanged (SC-003) ---
reset_scratch
sf=$(wf_name=bad seed "bad" "false")
before_sha=$(shasum "$sf" | awk '{print $1}')
out=$("$CLI" "reason" 2>&1) && rc=0 || rc=$?
after_sha=$(shasum "$sf" | awk '{print $1}')
if [[ "$rc" -eq 1 ]] && [[ "$out" == *"does not permit user input"* ]] && [[ "$before_sha" == "$after_sha" ]]; then
  assert_pass "permission denial exits 1, state byte-for-byte unchanged (SC-003)"
else
  assert_fail "permission denial: rc=$rc sha_match=[$before_sha==$after_sha] out=$out"
fi

# --- Case 5: WHEEL_NONINTERACTIVE=1 denies even on permitted step ---
reset_scratch
sf=$(wf_name=noni seed "noni" "true")
before_sha=$(shasum "$sf" | awk '{print $1}')
out=$(WHEEL_NONINTERACTIVE=1 "$CLI" "reason" 2>&1) && rc=0 || rc=$?
after_sha=$(shasum "$sf" | awk '{print $1}')
if [[ "$rc" -eq 1 ]] && [[ "$out" == *"non-interactive"* ]] && [[ "$before_sha" == "$after_sha" ]]; then
  assert_pass "WHEEL_NONINTERACTIVE=1 denies and leaves state unchanged (SC-004)"
else
  assert_fail "non-interactive: rc=$rc sha_match=[$before_sha==$after_sha] out=$out"
fi

# --- Case 6: empty-string reason → usage error ---
reset_scratch
sf=$(wf_name=empty seed "empty" "true")
out=$("$CLI" "" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ "$out" == *"usage:"* ]]; then
  assert_pass "empty-string reason rejected as usage error"
else
  assert_fail "empty-string reason: rc=$rc out=$out"
fi

# --- Case 7: ordering — permission gate runs before non-interactive gate ---
# This is important: a step without permission should get the permission
# message, not the non-interactive message, even when WHEEL_NONINTERACTIVE=1
# (both would deny, but FR-006 step 3 comes before step 4).
reset_scratch
sf=$(wf_name=ord seed "ord" "false")
out=$(WHEEL_NONINTERACTIVE=1 "$CLI" "reason" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ "$out" == *"does not permit user input"* ]]; then
  assert_pass "permission gate runs before non-interactive gate (FR-006 ordering)"
else
  assert_fail "ordering: expected permission denial first — rc=$rc out=$out"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
