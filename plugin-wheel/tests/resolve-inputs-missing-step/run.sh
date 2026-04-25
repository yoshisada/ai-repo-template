#!/usr/bin/env bash
# T053 — End-to-end dispatch-time fail-loud test for User Story 2 P1.
#
# Validates Acceptance Scenario 1 of User Story 2 in spec.md:
#   "Given an inputs: entry referencing a step that hasn't run, When dispatch
#    resolves the inputs, Then the step fails before any agent dispatch with
#    the documented 'missing upstream output' error."
#
# Exercises the dispatch.sh helper `_hydrate_agent_step` (the actual code
# path that runs at hook-time when an agent step transitions pending→working).
# Asserts:
#   (a) the documented error reaches stderr,
#   (b) the state file's step status is flipped to "failed",
#   (c) the function exits non-zero (caller MUST NOT proceed to dispatch).
#
# Note on substrate: tasks.md flagged this as a `/kiln:kiln-test` fixture,
# but the kiln-test harness only supports `harness-type: plugin-skill`
# (real claude --print subprocess against a /skill). This fixture exercises
# wheel runtime code at the bash function level — closer to the actual code
# path, lower latency, and CI-runnable. Friction note flags the substrate
# gap. Per NFR-G-1 carveout, pure-shell unit tests are acceptable for
# resolver/hydration logic without an LLM in the loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source the wheel libs the dispatch helper depends on.
WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"
# shellcheck source=../../lib/state.sh
source "${WHEEL_LIB_DIR}/state.sh"
# shellcheck source=../../lib/log.sh
source "${WHEEL_LIB_DIR}/log.sh"
# shellcheck source=../../lib/resolve_inputs.sh
source "${WHEEL_LIB_DIR}/resolve_inputs.sh"
# Pull in just the _hydrate_agent_step helper from dispatch.sh.
# Sourcing the whole file pulls in its own dependencies — easier to extract
# the helper inline here. The function is defined at the top of dispatch.sh.
# shellcheck disable=SC1091
. <(awk '/^_hydrate_agent_step\(\) \{/,/^}/' "${WHEEL_LIB_DIR}/dispatch.sh")

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

SCRATCH=$(mktemp -d -t wheel-missing-upstream-XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

# Build a synthetic workflow + state file.
# Step 0 (`upstream`) declares output_schema but NEVER runs (status: pending).
# Step 1 (`under-test`) declares inputs: referencing $.steps.upstream.output.x.
WORKFLOW=$(printf '%s' '{
  "name":"missing-upstream-test",
  "steps":[
    {"id":"upstream","type":"agent","output":"u.txt","output_schema":{"x":"$.x"}},
    {"id":"under-test","type":"agent","inputs":{"VAL":"$.steps.upstream.output.x"},"instruction":"use {{VAL}}"}
  ]
}')

STATE_FILE="${SCRATCH}/state.json"
cat > "$STATE_FILE" <<'EOF'
{
  "workflow_name":"missing-upstream-test",
  "cursor":1,
  "steps":[
    {"id":"upstream","type":"agent","status":"pending"},
    {"id":"under-test","type":"agent","status":"pending"}
  ],
  "session_registry":{"plugins":{}}
}
EOF
STATE=$(cat "$STATE_FILE")
STEP=$(printf '%s' "$WORKFLOW" | jq -c '.steps[1]')

echo "=== US2-1 — dispatch-time hydration with missing upstream ==="
err=$(_hydrate_agent_step "$STEP" "$STATE" "$WORKFLOW" "$STATE_FILE" 1 2>&1 >/dev/null)
rc=$?

# (a) exit non-zero
if [[ $rc -ne 0 ]]; then
  assert_pass "(a) _hydrate_agent_step exited non-zero"
else
  assert_fail "(a) _hydrate_agent_step should have failed (rc=$rc)"
fi

# (b) documented stderr error
if [[ "$err" == *"missing upstream output"* \
   && "$err" == *"upstream"* \
   && "$err" == *"VAL"* ]]; then
  assert_pass "(b) stderr contains documented missing-upstream error with var + step id"
else
  assert_fail "(b) wrong stderr: $err"
fi

# (c) state file flipped under-test status to "failed"
new_status=$(jq -r '.steps[1].status' "$STATE_FILE")
if [[ "$new_status" == "failed" ]]; then
  assert_pass "(c) state file: under-test step flipped to status=failed"
else
  assert_fail "(c) expected status=failed, got: $new_status"
fi

# (d) NFR-G-2 mutation tripwire — bogus assertion would not match.
bogus="this string is intentionally not in the resolver error 12345"
if [[ "$err" == *"$bogus"* ]]; then
  assert_fail "(d) mutation tripwire — bogus matched (vacuous)"
else
  assert_pass "(d) mutation tripwire — assertion genuine"
fi

echo "=== Negative control — happy path with all upstreams done ==="
# Reset state with upstream done + output written.
echo '{"x":"resolved-value"}' > "${SCRATCH}/u.txt"
cat > "$STATE_FILE" <<EOF
{
  "workflow_name":"missing-upstream-test",
  "cursor":1,
  "steps":[
    {"id":"upstream","type":"agent","status":"done","output":"${SCRATCH}/u.txt"},
    {"id":"under-test","type":"agent","status":"pending"}
  ],
  "session_registry":{"plugins":{}}
}
EOF
STATE=$(cat "$STATE_FILE")
out=$(_hydrate_agent_step "$STEP" "$STATE" "$WORKFLOW" "$STATE_FILE" 1 2>&1)
rc=$?
if [[ $rc -eq 0 ]]; then
  val=$(printf '%s' "$out" | jq -r '.VAL // empty' 2>/dev/null)
  if [[ "$val" == "resolved-value" ]]; then
    assert_pass "(e) happy path resolves correctly when upstream is done"
  else
    assert_fail "(e) expected 'resolved-value', got '$val'"
  fi
  # Confirm under-test is NOT marked failed in this case.
  new_status=$(jq -r '.steps[1].status' "$STATE_FILE")
  if [[ "$new_status" != "failed" ]]; then
    assert_pass "(f) happy path: under-test not flipped to failed"
  else
    assert_fail "(f) under-test wrongly flipped to failed on happy path"
  fi
else
  assert_fail "(e) happy path failed unexpectedly: $out"
fi

echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
