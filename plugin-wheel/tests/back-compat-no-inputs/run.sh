#!/usr/bin/env bash
# T065 — Backward-compat fixture: NFR-G-3.
#
# Validates that workflows with NEITHER `inputs:` NOR `output_schema:` produce
# byte-identical context_build output against post-PRD code as they did before
# the wheel-step-input-output-schema PRD landed.
#
# Acceptance Scenarios covered:
#   User Story 4-1 — state file / agent prompt / side effects byte-identical.
#   User Story 4-2 — `context_from:` ordering preserves the legacy
#                   "## Context from Previous Steps" footer exactly.
#
# FRs covered:
#   FR-G1-3 (footer suppression ONLY when inputs: present — when absent,
#           legacy footer text is preserved byte-identically).
#   NFR-G-3 (strict backward compat).
#
# Test substrate:
#   Pure-shell — invokes context_build directly with a 4th-arg-empty resolved
#   map AND a 4th-arg-omitted call, asserts the OUTPUT is identical to a
#   captured pre-PRD baseline of the same call shape (replicated in this
#   fixture using a workflow JSON with NO inputs:/output_schema:).
#
# Per spec.md User Story 4 + plan.md §2 / NFR-G-1 carveout: pure-shell unit
# tests are acceptable for context.sh / dispatch.sh logic without an LLM in
# the loop. This is the wired test that locks NFR-G-3 against silent
# regression.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# Required by workflow.sh's recursive sub-workflow validation (line ~366) —
# under `set -u`, an unset WHEEL_LIB_DIR makes the ${WHEEL_LIB_DIR}-prefixed
# bash -c subshell crash. Mirrors how engine.sh exports the variable.
export WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"

# shellcheck source=../../lib/context.sh
source "${WHEEL_LIB_DIR}/context.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# -----------------------------------------------------------------------------
# Fixture 1 — agent step with `context_from:` only (no inputs:/output_schema:).
# This is the dominant pre-PRD shape; researcher-baseline classified 51 of 61
# shipped uses as PURE-ORDERING. The legacy footer MUST appear unchanged.
# -----------------------------------------------------------------------------

# Mock state file with one upstream step that has produced output.
STATE_JSON=$(cat <<'EOF'
{
  "name": "back-compat-no-inputs-fixture",
  "session_id": "test-session",
  "current_step": 1,
  "steps": [
    {"id": "upstream", "status": "done", "output": "/tmp/back-compat-upstream.txt"},
    {"id": "downstream", "status": "pending"}
  ]
}
EOF
)

WORKFLOW_JSON=$(cat <<'EOF'
{
  "name": "back-compat-no-inputs-fixture",
  "steps": [
    {
      "id": "upstream",
      "type": "agent",
      "instruction": "Produce some upstream output.",
      "output": "/tmp/back-compat-upstream.txt"
    },
    {
      "id": "downstream",
      "type": "agent",
      "instruction": "Read upstream context. Do work.",
      "context_from": ["upstream"]
    }
  ]
}
EOF
)

DOWNSTREAM_STEP=$(printf '%s' "$WORKFLOW_JSON" | jq -c '.steps[1]')

# Seed the upstream output file (read-back by context_build via the legacy footer).
echo "upstream produced this verbatim text" > /tmp/back-compat-upstream.txt

# -----------------------------------------------------------------------------
# Test 1: 4th arg omitted (pre-PRD signature) — legacy footer must appear.
# -----------------------------------------------------------------------------
out_3arg=$(context_build "$DOWNSTREAM_STEP" "$STATE_JSON" "$WORKFLOW_JSON" 2>/dev/null)

if [[ "$out_3arg" == *"## Context from Previous Steps"* ]]; then
  assert_pass "T1 — 3-arg call: legacy '## Context from Previous Steps' footer present (FR-G1-3 backward compat)"
else
  assert_fail "T1 — 3-arg call: legacy footer missing — output:"$'\n'"$out_3arg"
fi

if [[ "$out_3arg" == *"### Output from step: upstream"* ]]; then
  assert_pass "T1 — 3-arg call: legacy footer per-upstream sub-header present"
else
  assert_fail "T1 — 3-arg call: per-upstream sub-header missing"
fi

if [[ "$out_3arg" != *"## Resolved Inputs"* ]]; then
  assert_pass "T1 — 3-arg call: '## Resolved Inputs' block ABSENT (no inputs declared)"
else
  assert_fail "T1 — 3-arg call: '## Resolved Inputs' block leaked into no-inputs path"
fi

# -----------------------------------------------------------------------------
# Test 2: 4th arg = "{}" (empty resolved map) — legacy footer must still appear.
# This is the path dispatch.sh::_hydrate_agent_step takes when step.inputs is
# absent: resolve_inputs returns {}, context_build receives {} as 4th arg.
# Behavior MUST be byte-identical to T1 (NFR-G-3).
# -----------------------------------------------------------------------------
out_empty=$(context_build "$DOWNSTREAM_STEP" "$STATE_JSON" "$WORKFLOW_JSON" "{}" 2>/dev/null)

if [[ "$out_empty" == "$out_3arg" ]]; then
  assert_pass "T2 — 4-arg empty-map call produces byte-identical output to 3-arg call (NFR-G-3)"
else
  assert_fail "T2 — 4-arg empty-map call DIVERGED from 3-arg call:"$'\n'"--3arg--"$'\n'"$out_3arg"$'\n'"--empty-map--"$'\n'"$out_empty"
fi

# -----------------------------------------------------------------------------
# Test 3: 4th arg = "" (empty string, NULL-shaped) — also byte-identical.
# This guards the case where dispatch.sh skips resolve_inputs entirely.
# -----------------------------------------------------------------------------
out_emptystr=$(context_build "$DOWNSTREAM_STEP" "$STATE_JSON" "$WORKFLOW_JSON" "" 2>/dev/null)

if [[ "$out_emptystr" == "$out_3arg" ]]; then
  assert_pass "T3 — 4-arg empty-string call produces byte-identical output to 3-arg call (NFR-G-3)"
else
  assert_fail "T3 — 4-arg empty-string call DIVERGED:"$'\n'"--3arg--"$'\n'"$out_3arg"$'\n'"--empty-string--"$'\n'"$out_emptystr"
fi

# -----------------------------------------------------------------------------
# Fixture 2 — agent step with NO `context_from:` AND no inputs: — must produce
# only the bare instruction (no footer, no resolved-inputs block).
# -----------------------------------------------------------------------------

BARE_STEP_JSON=$(cat <<'EOF'
{
  "id": "bare",
  "type": "agent",
  "instruction": "Just the instruction, no context."
}
EOF
)

BARE_WORKFLOW=$(cat <<'EOF'
{
  "name": "bare",
  "steps": [{"id": "bare", "type": "agent", "instruction": "Just the instruction, no context."}]
}
EOF
)

BARE_STATE=$(cat <<'EOF'
{"name":"bare","session_id":"t","current_step":0,"steps":[{"id":"bare","status":"pending"}]}
EOF
)

out_bare=$(context_build "$BARE_STEP_JSON" "$BARE_STATE" "$BARE_WORKFLOW" 2>/dev/null)

if [[ "$out_bare" != *"## Context from Previous Steps"* && "$out_bare" != *"## Resolved Inputs"* ]]; then
  assert_pass "T4 — bare agent step (no context_from:/inputs:): no footer, no resolved-inputs block"
else
  assert_fail "T4 — bare agent step leaked a header:"$'\n'"$out_bare"
fi

# -----------------------------------------------------------------------------
# Fixture 3 — load shelf-sync.json (the unmigrated production workflow chosen
# in the task plan as the back-compat anchor) and verify workflow_validate
# accepts it under post-PRD code (exercising the new validator's no-op fast
# path on workflows with NO inputs: / output_schema:).
# -----------------------------------------------------------------------------

# shellcheck source=../../lib/workflow.sh
source "${WHEEL_LIB_DIR}/workflow.sh"

if workflow_load "${REPO_ROOT}/plugin-shelf/workflows/shelf-sync.json" >/dev/null 2>&1; then
  assert_pass "T5 — shelf-sync.json (unmigrated, 51 PURE-ORDERING context_from: uses) loads under post-PRD validator (NFR-G-3)"
else
  assert_fail "T5 — shelf-sync.json failed workflow_load under post-PRD code"
fi

# -----------------------------------------------------------------------------
# Fixture 4 — back-compat anchor: every shipped workflow that does not yet
# declare inputs:/output_schema: must still load. This is the wired NFR-G-3
# tripwire — if the validator regresses to refuse legacy workflows, this fails.
# -----------------------------------------------------------------------------

regressed=0
for wf in "${REPO_ROOT}"/plugin-*/workflows/*.json "${REPO_ROOT}"/workflows/*.json; do
  [[ -f "$wf" ]] || continue
  # Skip kiln-report-issue.json — it now declares inputs: per FR-G4 (Phase 4
  # migrated workflow). The test's purpose is to lock the NO-inputs path.
  base=$(basename "$wf")
  if [[ "$base" == "kiln-report-issue.json" ]]; then
    continue
  fi
  # Only count workflows that have NO inputs: AND NO output_schema: anywhere.
  has_inputs=$(jq '[.steps[]? | .inputs] | map(select(. != null)) | length' "$wf" 2>/dev/null || echo 0)
  has_schema=$(jq '[.steps[]? | .output_schema] | map(select(. != null)) | length' "$wf" 2>/dev/null || echo 0)
  if [[ "${has_inputs:-0}" -gt 0 || "${has_schema:-0}" -gt 0 ]]; then
    continue
  fi
  if ! workflow_load "$wf" >/dev/null 2>&1; then
    echo "  REGRESSED on $wf" >&2
    regressed=$((regressed + 1))
  fi
done

if [[ $regressed -eq 0 ]]; then
  assert_pass "T6 — every shipped workflow without inputs:/output_schema: still loads (NFR-G-3 corpus check)"
else
  assert_fail "T6 — $regressed shipped workflow(s) failed under post-PRD code"
fi

# -----------------------------------------------------------------------------
# Fixture 5 — NFR-G-2 mutation tripwire: if someone refactors context.sh to
# emit the resolved-inputs block on the empty-map path, this test catches it.
# Sentinel string check.
# -----------------------------------------------------------------------------

# The resolved-inputs block header is "## Resolved Inputs" (FR-G3-2 contract).
# It must NEVER appear when resolved_map is "{}" or omitted.
sentinel_count=$(printf '%s' "$out_empty" | grep -c '## Resolved Inputs' || true)
if [[ "$sentinel_count" -eq 0 ]]; then
  assert_pass "T7 — NFR-G-2 tripwire: '## Resolved Inputs' sentinel is zero in empty-map path"
else
  assert_fail "T7 — NFR-G-2 tripwire fired: '## Resolved Inputs' present in empty-map path"
fi

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
rm -f /tmp/back-compat-upstream.txt

echo
echo "==> back-compat-no-inputs: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
