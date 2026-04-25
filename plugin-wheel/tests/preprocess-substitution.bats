#!/usr/bin/env bats
# preprocess-substitution.bats
# Pure-shell tests for plugin-wheel/lib/preprocess.sh::template_workflow_json.
#
# Covers (per tasks.md T025):
#   - Token substitution (${WHEEL_PLUGIN_<name>}, ${WORKFLOW_PLUGIN_DIR})
#   - Escape decoding ($${...} -> literal ${...})
#   - Idempotence (I-P-5)
#   - Generic ${VAR} passthrough (EC-4)
#
# Acceptance scenarios traced:
#   - spec.md AS-F-4 (preprocessor swap honors substitution)
#   - contracts/interfaces.md §3 invariants I-P-1, I-P-3, I-P-4, I-P-5
#   - research.md §2.A (token grammar) and §2.B (escape grammar)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/plugin-wheel/lib/preprocess.sh"
  REG_SHELF=$(jq -nc '{schema_version:1,built_at:"now",source:"candidate-a-path-parsing",fallback_used:false,plugins:{shelf:"/abs/shelf",kiln:"/abs/kiln"}}')
  REG_EMPTY=$(jq -nc '{schema_version:1,built_at:"now",source:"candidate-a-path-parsing",fallback_used:false,plugins:{}}')
}

# ---- Token substitution -----------------------------------------------------

@test "WHEEL_PLUGIN token substitutes from registry" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"path is ${WHEEL_PLUGIN_shelf}/x.sh"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "path is /abs/shelf/x.sh"' >/dev/null
}

@test "WORKFLOW_PLUGIN_DIR substitutes against calling_plugin_dir (FR-F4-3)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"${WORKFLOW_PLUGIN_DIR}/scripts/foo.sh"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/plugin-kiln"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "/abs/plugin-kiln/scripts/foo.sh"' >/dev/null
}

@test "Multiple WHEEL_PLUGIN tokens in one instruction all substitute" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"${WHEEL_PLUGIN_shelf}/a && ${WHEEL_PLUGIN_kiln}/b"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "/abs/shelf/a && /abs/kiln/b"' >/dev/null
}

@test "Plugin name with hyphen is supported by token grammar (I-P-2)" {
  reg=$(jq -nc '{schema_version:1,plugins:{"my-plugin":"/abs/my-plugin"}}')
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"${WHEEL_PLUGIN_my-plugin}/x"}]}')
  run template_workflow_json "$wf" "$reg" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "/abs/my-plugin/x"' >/dev/null
}

@test "Command steps are untouched (FR-F4-2 — only agent.instruction is preprocessed)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"c1",type:"command",command:"echo ${WHEEL_PLUGIN_shelf}/foo"},{id:"a1",type:"agent",instruction:"${WHEEL_PLUGIN_shelf}/x"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].command == "echo ${WHEEL_PLUGIN_shelf}/foo"' >/dev/null
  echo "$output" | jq -e '.steps[1].instruction == "/abs/shelf/x"' >/dev/null
}

# ---- Escape decoding (research §2.B / I-P-3) --------------------------------

@test "Escaped \$\${WHEEL_PLUGIN_shelf} survives as literal \${WHEEL_PLUGIN_shelf}" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"docs say $${WHEEL_PLUGIN_shelf}"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "docs say ${WHEEL_PLUGIN_shelf}"' >/dev/null
}

@test "Escaped \$\${WORKFLOW_PLUGIN_DIR} survives as literal \${WORKFLOW_PLUGIN_DIR}" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"see $${WORKFLOW_PLUGIN_DIR} for syntax"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "see ${WORKFLOW_PLUGIN_DIR} for syntax"' >/dev/null
}

@test "Mixed escaped + unescaped tokens — escape preserved, real token substituted" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"use ${WHEEL_PLUGIN_shelf}, escape with $${WHEEL_PLUGIN_shelf}"}]}')
  run template_workflow_json "$wf" "$REG_SHELF" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "use /abs/shelf, escape with ${WHEEL_PLUGIN_shelf}"' >/dev/null
}

# ---- Idempotence (I-P-5) -----------------------------------------------------

@test "Calling template_workflow_json twice is a no-op on the second pass" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"${WHEEL_PLUGIN_shelf}/x"}]}')
  pass1=$(template_workflow_json "$wf" "$REG_SHELF" "/abs/caller")
  pass2=$(template_workflow_json "$pass1" "$REG_SHELF" "/abs/caller")
  [ "$pass1" = "$pass2" ]
}

@test "Idempotent when instruction has no plugin tokens at all" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"plain text, no tokens"}]}')
  pass1=$(template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller")
  pass2=$(template_workflow_json "$pass1" "$REG_EMPTY" "/abs/caller")
  [ "$pass1" = "$pass2" ]
  echo "$pass1" | jq -e '.steps[0].instruction == "plain text, no tokens"' >/dev/null
}

# ---- Generic ${VAR} passthrough (EC-4 / I-P-4) ------------------------------

@test "Bash array iteration syntax \${files[@]} passes through unchanged" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"for f in ${files[@]}; do echo $f; done"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "for f in ${files[@]}; do echo $f; done"' >/dev/null
}

@test "Generic env var \${HOME} passes through unchanged (narrowed-pattern tripwire)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"path = ${HOME}/code"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "path = ${HOME}/code"' >/dev/null
}

@test "Single-dollar \$ outside braces passes through (no false positive)" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:"price is $5 and $7"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == "price is $5 and $7"' >/dev/null
}

# ---- Backward compat (NFR-F-5) ---------------------------------------------

@test "Workflow without requires_plugins and no plugin tokens is byte-identical" {
  wf=$(jq -nc '{name:"t",version:"1",steps:[{id:"c1",type:"command",command:"echo hi"}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 0 ]
  [ "$output" = "$wf" ]
}

@test "Empty instruction is preserved unchanged" {
  wf=$(jq -nc '{name:"t",steps:[{id:"s1",type:"agent",instruction:""}]}')
  run template_workflow_json "$wf" "$REG_EMPTY" "/abs/caller"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].instruction == ""' >/dev/null
}
