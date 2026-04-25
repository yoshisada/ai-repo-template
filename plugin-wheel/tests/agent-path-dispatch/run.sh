#!/usr/bin/env bash
# T042 / T043 / T044 — Workflow agent_path dispatch tests.
#
# Covers contracts/interfaces.md §2 "Tests":
#   T042: agent_path: debugger         -> spec.system_prompt_path points at
#                                         plugin-wheel/agents/debugger.md
#                                         (or equivalent absolute/$WORKFLOW_PLUGIN_DIR-rooted).
#   T043: agent_path absent            -> fragment is {"agent_path": null}
#                                         (NFR-5 byte-identical shape).
#   T044: agent_path: <nonsense>       -> loud exit 1 with identifiable error string.
#
# Tests invoke `dispatch_agent_step_path` (sourced) against synthetic step-JSON
# rather than spawning a live orchestrator — orchestrator integration is a
# downstream concern covered by the audit step's end-to-end review. This
# isolates the I-A1/I-A3/I-A4 invariants to their owning helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source the helper. set +u temporarily because the helper sources with set -eu
# and the surrounding test framework would also want -u on.
# shellcheck source=../../scripts/dispatch/dispatch-agent-step.sh
source "${REPO_ROOT}/plugin-wheel/scripts/dispatch/dispatch-agent-step.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

cd "$REPO_ROOT"

# --- T042: agent_path: debugger → full resolver spec wrapped under agent_path ---
step_json='{"type":"agent","name":"t042-step","agent_path":"debugger"}'
out=$(dispatch_agent_step_path "$step_json")
subagent=$(jq -r '.agent_path.subagent_type' <<<"$out")
sys_path=$(jq -r '.agent_path.system_prompt_path' <<<"$out")
source_val=$(jq -r '.agent_path.source' <<<"$out")
model_default=$(jq -r '.agent_path.model_default' <<<"$out")
if [[ "$subagent" == "debugger" \
      && "$source_val" == "short-name" \
      && "$model_default" == "sonnet" \
      && "$sys_path" == *"plugin-wheel/agents/debugger.md" ]]; then
  assert_pass "T042: agent_path:debugger → debugger spec wrapped correctly"
else
  assert_fail "T042: subagent=$subagent source=$source_val model=$model_default sys_path=$sys_path"
fi

# --- T043: agent_path absent → {"agent_path": null} (I-A1, NFR-5) ---
step_json='{"type":"agent","name":"t043-step","subagent_type":"general-purpose"}'
out=$(dispatch_agent_step_path "$step_json")
null_shape=$(jq -c '.' <<<"$out")
if [[ "$null_shape" == '{"agent_path":null}' ]]; then
  assert_pass "T043: absent agent_path → {\"agent_path\":null} (NFR-5)"
else
  assert_fail "T043: expected {\"agent_path\":null} got: $null_shape"
fi

# --- T044: agent_path: <nonsense> → loud exit 1 ---
step_json='{"type":"agent","name":"t044-step","agent_path":"./nope/does-not-exist.md"}'
tmp_err="$(mktemp -t wheel-t044.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -f '$tmp_err'" EXIT
# Unset WORKFLOW_PLUGIN_DIR in this subshell so the relative path truly can't resolve.
set +e
( env -u WORKFLOW_PLUGIN_DIR bash -c "
  source '${REPO_ROOT}/plugin-wheel/scripts/dispatch/dispatch-agent-step.sh'
  dispatch_agent_step_path '$step_json'
" ) 1>/dev/null 2>"$tmp_err"
rc=$?
set -e
err=$(cat "$tmp_err")
if [[ "$rc" -ne 0 && "$err" == *"wheel: agent_path resolution failed for step 't044-step'"* ]]; then
  assert_pass "T044: nonsense agent_path → loud exit $rc with step-tagged error"
else
  assert_fail "T044: expected exit non-zero + step-tagged stderr; got rc=$rc err=$err"
fi

# --- I-A3 (passthrough): agent_path: <unknown-short-name> → source=unknown ---
step_json='{"type":"agent","name":"passthrough-step","agent_path":"imaginary-agent"}'
out=$(dispatch_agent_step_path "$step_json")
source_val=$(jq -r '.agent_path.source' <<<"$out")
subagent=$(jq -r '.agent_path.subagent_type' <<<"$out")
if [[ "$source_val" == "unknown" && "$subagent" == "imaginary-agent" ]]; then
  assert_pass "I-A3: unknown short name → source=unknown, subagent echoed (back-compat preserved)"
else
  assert_fail "I-A3: source=$source_val subagent=$subagent"
fi

# --- Summary ---
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
