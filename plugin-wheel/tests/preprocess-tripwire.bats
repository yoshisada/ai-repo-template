#!/usr/bin/env bats
# preprocess-tripwire.bats
# Pure-shell tests for the FR-F4-5 narrowed-pattern tripwire in
# plugin-wheel/lib/preprocess.sh::template_workflow_json.
#
# Covers (per tasks.md T026 — four documented residual cases):
#   1. Unsubstituted token (registry has the name but the regex shape was
#      malformed somehow — defense-in-depth path).
#   2. Unknown name (registry doesn't have the plugin — should normally be
#      caught by resolve.sh, this is the second line of defense per I-P
#      contract).
#   3. Malformed escape (e.g. `${WORKFLOW_PLUGIN_DIR` with no closing
#      brace, or `${WHEEL_PLUGIN_some.dotted.name}` whose name doesn't
#      match the strict grammar).
#   4. Tripwire exact error text — verbatim FR-F4-5 documented string,
#      including step id.
#
# NFR-F-2 silent-failure tripwire: each test asserts the EXACT documented
# error text. If a future refactor changes the wording, the test fails
# loudly — by construction the regression cannot ship green.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/plugin-wheel/lib/preprocess.sh"
  REG_EMPTY=$(jq -nc '{schema_version:1,plugins:{}}')
  REG_SHELF=$(jq -nc '{schema_version:1,plugins:{shelf:"/abs/shelf"}}')
}

# Per FR-F4-5 / contracts §3 the error text is the FR-F4-5 line PLUS the
# FR-016 documentary-references line (specs/merge-pr-and-sc-grep-guidance):
#   Wheel preprocessor failed: instruction text for step '<id>' still contains '${...}'. This is a wheel runtime bug; please file an issue.
#   If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.
EXPECTED_ERROR_TEMPLATE="Wheel preprocessor failed: instruction text for step '%s' still contains '\${...}'. This is a wheel runtime bug; please file an issue.
If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with \$\$ escaping."

# ---- Case 1: unknown plugin name (resolver bypass scenario) ------------------

@test "Tripwire fires on \${WHEEL_PLUGIN_unknown} when registry doesn't have 'unknown'" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s9",type:"agent",instruction:"${WHEEL_PLUGIN_unknown}/x"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "s9")
  [ "$output" = "$expected" ]
}

@test "Tripwire fires when registry has 'shelf' but instruction asks for 'kiln'" {
  wf=$(jq -nc '{name:"t",steps:[{id:"step-cross",type:"agent",instruction:"${WHEEL_PLUGIN_kiln}/x"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "step-cross")
  [ "$output" = "$expected" ]
}

# ---- Case 2: malformed token (unclosed brace) --------------------------------

@test "Tripwire fires on unclosed token \${WHEEL_PLUGIN_shelf (no closing brace)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"unclosed",type:"agent",instruction:"path is ${WHEEL_PLUGIN_shelf without close"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "unclosed")
  [ "$output" = "$expected" ]
}

@test "Tripwire fires on unclosed \${WORKFLOW_PLUGIN_DIR with no closing brace" {
  wf=$(jq -nc '{name:"t",steps:[{id:"workflow-unclosed",type:"agent",instruction:"see ${WORKFLOW_PLUGIN_DIR/scripts/foo"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "workflow-unclosed")
  [ "$output" = "$expected" ]
}

# ---- Case 3: name that doesn't match strict grammar [a-zA-Z0-9_-]+ -----------

@test "Tripwire fires when plugin name contains a dot (grammar violation, I-P-2)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"dotted",type:"agent",instruction:"${WHEEL_PLUGIN_some.dotted.name}/x"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "dotted")
  [ "$output" = "$expected" ]
}

@test "Tripwire fires when plugin name contains a slash (grammar violation)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"slashed",type:"agent",instruction:"${WHEEL_PLUGIN_a/b}/x"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "slashed")
  [ "$output" = "$expected" ]
}

# ---- Case 4: error text exact match ------------------------------------------

@test "Tripwire error text matches the FR-F4-5 + FR-016 documented string verbatim" {
  wf=$(jq -nc '{name:"t",steps:[{id:"exact",type:"agent",instruction:"${WHEEL_PLUGIN_missing}"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  # exact, full, byte-for-byte — both the FR-F4-5 line and the FR-016 documentary-references line:
  expected="Wheel preprocessor failed: instruction text for step 'exact' still contains '\${...}'. This is a wheel runtime bug; please file an issue.
If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with \$\$ escaping."
  [ "$output" = "$expected" ]
}

# ---- FR-016 documentary-references rule (specs/merge-pr-and-sc-grep-guidance) ----

@test "Tripwire error text contains the FR-016 documentary-references line" {
  wf=$(jq -nc '{name:"t",steps:[{id:"doc",type:"agent",instruction:"${WHEEL_PLUGIN_missing}"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  # SC-006 sentinel: the documentary-references rule MUST be in the rendered stderr
  # so authors hit the explanation on first violation rather than rediscovering it.
  echo "$output" | grep -qF "If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with \$\$ escaping."
}

@test "Tripwire firing on first offending step short-circuits — error text names that step" {
  wf=$(jq -nc '{name:"t",steps:[
    {id:"first",type:"agent",instruction:"plain text"},
    {id:"second",type:"agent",instruction:"${WHEEL_PLUGIN_missing}"},
    {id:"third",type:"agent",instruction:"${WHEEL_PLUGIN_alsomissing}"}
  ]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  expected=$(printf "$EXPECTED_ERROR_TEMPLATE" "second")
  [ "$output" = "$expected" ]
}

# ---- NFR-F-2 silent-failure guard --------------------------------------------

@test "Mutating the documented error text MUST cause this assertion to fail" {
  wf=$(jq -nc '{name:"t",steps:[{id:"any",type:"agent",instruction:"${WHEEL_PLUGIN_missing}"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 1 ]
  # If a refactor changes "Wheel preprocessor failed" to anything else,
  # this grep returns 1 and the test fails — which is the whole point.
  echo "$output" | grep -q "^Wheel preprocessor failed: instruction text for step "
}

@test "Tripwire never fires for a workflow with zero residuals (no false positives)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"clean",type:"agent",instruction:"${WHEEL_PLUGIN_shelf}/x and ${WORKFLOW_PLUGIN_DIR}/y"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "/abs/shelf/x and /abs/caller/y"' >/dev/null
}
