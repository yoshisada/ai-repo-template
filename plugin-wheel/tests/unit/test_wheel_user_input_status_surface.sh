#!/usr/bin/env bash
# FR-015 (wheel-user-input): /wheel:wheel-status shows pending-user-input rows
# with reason and elapsed-time formatting. Covers US7; SC-006 accuracy gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS_BIN="${PLUGIN_DIR}/bin/wheel-status"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

scratch="$(mktemp -d -t wheel-status.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
mkdir -p .wheel

# --- Case 1: no workflows → friendly message ---
out=$("$STATUS_BIN" 2>&1)
if [[ "$out" == *"No workflows are currently running"* ]]; then
  assert_pass "no workflows → friendly message"
else
  assert_fail "no-workflow output: $out"
fi

# --- Case 2: one workflow NOT awaiting input → no [awaiting input] row ---
wf="${scratch}/wf.json"
jq -n '{name: "w", steps: [{id: "s", type: "agent"}]}' > "$wf"
state="${scratch}/.wheel/state_a.json"
jq -n --arg wf "$wf" '{
  workflow_name: "w", workflow_version: "1", workflow_file: $wf,
  status: "running", cursor: 0,
  owner_session_id: "sid", owner_agent_id: "aid",
  started_at: "2026-04-24T00:00:00Z", updated_at: "2026-04-24T00:00:00Z",
  steps: [{id: "s", type: "agent", status: "working"}]
}' > "$state"

out=$("$STATUS_BIN" 2>&1)
if [[ "$out" != *"awaiting input"* ]]; then
  assert_pass "non-awaiting workflow: no [awaiting input] row"
else
  assert_fail "unexpected [awaiting input] row: $out"
fi

# --- Case 3: workflow awaiting input set 4 minutes ago → row + elapsed ≈ 4m ---
SINCE_EPOCH=$(( $(date -u +%s) - 240 ))   # 4 minutes ago
# Format as ISO-8601.
if date -u -r "$SINCE_EPOCH" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  SINCE=$(date -u -r "$SINCE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
else
  SINCE=$(date -u -d "@${SINCE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)
fi
jq --arg since "$SINCE" '
  .steps[0].awaiting_user_input = true
  | .steps[0].awaiting_user_input_since = $since
  | .steps[0].awaiting_user_input_reason = "need phase assignment"
' "$state" > "${state}.tmp" && mv "${state}.tmp" "$state"

out=$("$STATUS_BIN" 2>&1)
if [[ "$out" == *"[awaiting input] w / step 's'"* ]] && [[ "$out" == *"reason=need phase assignment"* ]]; then
  assert_pass "awaiting row includes workflow, step id, and reason"
else
  assert_fail "awaiting row missing expected fields: $out"
fi

# Elapsed time should be ~4 minutes (tolerate ±10s per SC-006).
elapsed_line=$(echo "$out" | grep "awaiting input")
if [[ "$elapsed_line" =~ elapsed=([0-9]+)m[[:space:]]*([0-9]+)s ]]; then
  mins="${BASH_REMATCH[1]}"
  secs="${BASH_REMATCH[2]}"
  total=$((mins * 60 + secs))
  if [[ "$total" -ge 230 ]] && [[ "$total" -le 250 ]]; then
    assert_pass "elapsed time ≈ 4m (got ${mins}m ${secs}s = ${total}s, within ±10s of 240s per SC-006)"
  else
    assert_fail "elapsed time drift: got ${total}s, expected 240±10s"
  fi
else
  assert_fail "elapsed did not match Nm Ss pattern: $elapsed_line"
fi

# --- Case 4: elapsed < 60s uses Ns format ---
# Set awaiting_user_input_since to ~15 seconds ago
SINCE_EPOCH2=$(( $(date -u +%s) - 15 ))
if date -u -r "$SINCE_EPOCH2" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  SINCE2=$(date -u -r "$SINCE_EPOCH2" +%Y-%m-%dT%H:%M:%SZ)
else
  SINCE2=$(date -u -d "@${SINCE_EPOCH2}" +%Y-%m-%dT%H:%M:%SZ)
fi
jq --arg since "$SINCE2" '.steps[0].awaiting_user_input_since = $since' "$state" > "${state}.tmp" && mv "${state}.tmp" "$state"
out=$("$STATUS_BIN" 2>&1)
elapsed_line=$(echo "$out" | grep "awaiting input")
if [[ "$elapsed_line" == *"elapsed="*"m"* ]]; then
  assert_fail "expected Ns format for <60s elapsed (no m component), got: $elapsed_line"
elif [[ "$elapsed_line" =~ elapsed=([0-9]+)s ]]; then
  secs="${BASH_REMATCH[1]}"
  if [[ "$secs" -ge 10 ]] && [[ "$secs" -le 25 ]]; then
    assert_pass "elapsed < 60s uses Ns format (got ${secs}s)"
  else
    assert_fail "elapsed drift: got ${secs}s, expected ~15s"
  fi
else
  assert_fail "expected Ns format for <60s elapsed, got: $elapsed_line"
fi

# --- Case 5: additive — other status rows still present ---
if [[ "$out" == *"Workflow: w"* ]] && [[ "$out" == *"Step:"* ]] && [[ "$out" == *"Started:"* ]]; then
  assert_pass "existing status rows preserved (additive-only change)"
else
  assert_fail "existing rows missing: $out"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
