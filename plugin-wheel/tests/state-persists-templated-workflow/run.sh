#!/usr/bin/env bash
# Regression fixture for cross-plugin-resolver state-persistence bug.
#
# Bug shipped in PR #163 (cross-plugin-resolver-and-preflight-registry):
# post-tool-use.sh templated the workflow JSON correctly via preprocess.sh,
# but state_init persisted only step metadata (id, type, status) — not the
# templated `instruction` field. Every subsequent hook re-loaded the RAW
# workflow_file from disk via engine_init → workflow_load, leaking
# unsubstituted ${WHEEL_PLUGIN_<name>} tokens to agent prompts.
#
# Original audit was 8/8 fixtures green because all fixtures tested
# template_workflow_json in isolation OR the activate path. NO fixture
# tested the activate → state → stop-hook → agent-prompt round-trip.
#
# This fixture covers that gap. It:
#   1. Templates a workflow with a ${WHEEL_PLUGIN_shelf} token
#   2. Calls state_init with the templated JSON
#   3. Asserts state.workflow_definition.steps[0].instruction is substituted
#   4. Calls engine_init (simulating what stop.sh does on every step)
#   5. Asserts WORKFLOW (the global engine_init sets) contains substituted text

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIB_DIR="$REPO_ROOT/plugin-wheel/lib"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

cd "$TMP_DIR"

# --- Source the wheel libs (engine.sh expects siblings in same dir, so source via cd) ---
cd "$LIB_DIR"
source ./log.sh
source ./state.sh
source ./registry.sh
source ./resolve.sh
source ./preprocess.sh
source ./workflow.sh
source ./engine.sh
cd "$TMP_DIR"

# --- Workflow JSON with a cross-plugin token ---
cat > workflow.json <<'JSON'
{
  "name": "round-trip-test",
  "version": "1.0.0",
  "requires_plugins": ["shelf"],
  "steps": [
    {
      "id": "round-trip-step",
      "type": "agent",
      "instruction": "Run: bash \"${WHEEL_PLUGIN_shelf}/scripts/foo.sh\""
    }
  ]
}
JSON

WF_JSON=$(jq -c '.' workflow.json)

# --- Fake registry (avoid relying on real plugin install) ---
FAKE_SHELF_PATH="/tmp/fake-shelf-path-for-test"
REG_JSON=$(jq -nc --arg path "$FAKE_SHELF_PATH" '{
  schema_version: 1,
  built_at: "2026-04-25T00:00:00Z",
  source: "test-fixture",
  fallback_used: false,
  plugins: { shelf: $path }
}')

# --- Template the workflow ---
TEMPLATED=$(template_workflow_json "$WF_JSON" "$REG_JSON" "/abs/calling/plugin")

# --- Assert template_workflow_json itself produced the substitution ---
templated_instr=$(printf '%s' "$TEMPLATED" | jq -r '.steps[0].instruction')
expected_instr="Run: bash \"${FAKE_SHELF_PATH}/scripts/foo.sh\""
if [[ "$templated_instr" != "$expected_instr" ]]; then
  echo "FAIL: template_workflow_json did not substitute correctly"
  echo "  expected: $expected_instr"
  echo "  got:      $templated_instr"
  exit 1
fi

# --- state_init should embed workflow_definition with templated instruction ---
state_init "$TMP_DIR/test-state.json" "$TEMPLATED" "test-session" "test-agent" "$TMP_DIR/workflow.json"

if ! jq -e 'has("workflow_definition")' "$TMP_DIR/test-state.json" >/dev/null; then
  echo "FAIL: state_init did not embed workflow_definition"
  echo "  state file keys: $(jq -r 'keys[]' "$TMP_DIR/test-state.json" | tr '\n' ' ')"
  exit 1
fi

embedded_instr=$(jq -r '.workflow_definition.steps[0].instruction' "$TMP_DIR/test-state.json")
if [[ "$embedded_instr" != "$expected_instr" ]]; then
  echo "FAIL: state.workflow_definition.steps[0].instruction does not contain templated path"
  echo "  expected: $expected_instr"
  echo "  got:      $embedded_instr"
  exit 1
fi

# --- engine_init should prefer state.workflow_definition over workflow_file ---
# Sabotage the workflow_file: replace its instruction with raw token,
# proving engine_init reads from state, not from disk.
cat > "$TMP_DIR/workflow.json" <<'JSON'
{
  "name": "round-trip-test",
  "version": "1.0.0",
  "requires_plugins": ["shelf"],
  "steps": [
    {
      "id": "round-trip-step",
      "type": "agent",
      "instruction": "RAW_FILE_INSTRUCTION_THAT_SHOULD_NOT_BE_USED"
    }
  ]
}
JSON

unset WORKFLOW
engine_init "$TMP_DIR/workflow.json" "$TMP_DIR/test-state.json"

final_instr=$(printf '%s' "$WORKFLOW" | jq -r '.steps[0].instruction')
if [[ "$final_instr" != "$expected_instr" ]]; then
  echo "FAIL: engine_init did not prefer state.workflow_definition over workflow_file"
  echo "  expected (from state):  $expected_instr"
  echo "  got (from raw file?):   $final_instr"
  exit 1
fi

# --- Tripwire: assert the unsubstituted token is NOT in the final WORKFLOW ---
if printf '%s' "$WORKFLOW" | grep -q '\${WHEEL_PLUGIN_'; then
  echo "FAIL: unsubstituted \${WHEEL_PLUGIN_*} token leaked into engine_init output"
  exit 1
fi

# --- Backward compat: state file WITHOUT workflow_definition falls back to file ---
jq 'del(.workflow_definition)' "$TMP_DIR/test-state.json" > "$TMP_DIR/state-no-wf.json"
unset WORKFLOW
engine_init "$TMP_DIR/workflow.json" "$TMP_DIR/state-no-wf.json"
fallback_instr=$(printf '%s' "$WORKFLOW" | jq -r '.steps[0].instruction')
if [[ "$fallback_instr" != "RAW_FILE_INSTRUCTION_THAT_SHOULD_NOT_BE_USED" ]]; then
  echo "FAIL: legacy state without workflow_definition did not fall back to workflow_file"
  echo "  expected (from file): RAW_FILE_INSTRUCTION_THAT_SHOULD_NOT_BE_USED"
  echo "  got:                  $fallback_instr"
  exit 1
fi

echo "PASS: state-persists-templated-workflow round-trip"
echo "  - template_workflow_json: substitutes correctly"
echo "  - state_init: embeds workflow_definition"
echo "  - engine_init: prefers state.workflow_definition over workflow_file"
echo "  - tripwire: no unsubstituted tokens in final WORKFLOW"
echo "  - backward compat: legacy state falls back to workflow_load"
