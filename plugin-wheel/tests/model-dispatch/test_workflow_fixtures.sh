#!/usr/bin/env bash
# FR-B1 / FR-B2 / NFR-5 — Workflow-level integration tests for the per-step
# model selection path. Exercises realistic workflow JSON fragments and
# asserts the spawn-clause produced by wheel's teammate dispatch.
#
# Covers tasks.md T061 (model-haiku-dispatch / SC-006), T062 (model-loud-fail),
# and T063 (backward-compat-no-model / NFR-5 byte-identical).
#
# Fixtures live under fixtures/ as standalone workflow JSON files so a reviewer
# can read them end-to-end. Each case constructs a minimal teammate-step-like
# payload, extracts `.model` the same way `_teammate_flush_from_state` does,
# and pipes it through `dispatch_agent_step_model_clause`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${PLUGIN_DIR}/scripts/dispatch/dispatch-agent-step.sh"
FIXTURES="${SCRIPT_DIR}/fixtures"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Replay what lib/dispatch.sh's _teammate_flush_from_state does: extract
# `.steps[] | select(.type == "teammate" and .id == $aid) | .model`.
extract_model_for_agent() {
  local workflow_json="$1"
  local agent_id="$2"
  jq -r --arg aid "${agent_id}" \
    '[.steps[] | select(.type == "teammate" and (.id == $aid or .name == $aid))] | .[0].model // empty' \
    <<<"${workflow_json}"
}

# --- T061 / SC-006: model-haiku-dispatch ---
# Anchor test for SC-006. A shipped test workflow uses `model: haiku` on a
# classification-style teammate step; the dispatch-time clause MUST carry
# the resolved claude-haiku-* id into the Agent() spawn instruction.
echo ""
echo "--- T061 / SC-006: model-haiku-dispatch ---"
workflow=$(cat "${FIXTURES}/model-haiku-dispatch.json")
model=$(extract_model_for_agent "${workflow}" "classify-entries")
if [[ "${model}" != "haiku" ]]; then
  assert_fail "fixture regression — expected model=haiku on classify-entries, got '${model}'"
else
  clause=$("${HELPER}" model-clause classify-entries "${model}")
  if [[ "${clause}" == *"model='claude-haiku-"* ]]; then
    assert_pass "T061/SC-006 — shipped workflow with model: haiku threads claude-haiku-* into spawn clause"
  else
    assert_fail "T061/SC-006 — clause missing claude-haiku-* id — got '${clause}'"
  fi
fi

# --- T062: model-loud-fail ---
# FR-B2 invariant. A workflow using an unrecognized model id MUST NOT
# silently fall back. The spawn clause MUST carry ACTIVATION ERROR.
echo ""
echo "--- T062: model-loud-fail ---"
workflow=$(cat "${FIXTURES}/model-loud-fail.json")
model=$(extract_model_for_agent "${workflow}" "malformed-step")
if [[ "${model}" != "gpt-4" ]]; then
  assert_fail "fixture regression — expected model=gpt-4 (admission-regex-failing), got '${model}'"
else
  clause=$("${HELPER}" model-clause malformed-step "${model}")
  if [[ "${clause}" == *"ACTIVATION ERROR"* ]]; then
    assert_pass "T062 — malformed model id produces ACTIVATION ERROR clause (FR-B2)"
  else
    assert_fail "T062 — silent-fallback regression — got '${clause}'"
  fi
  # NFR-2 inversion: the clause MUST NOT contain a "Spawn this agent with model="
  # success marker on the loud-fail path.
  if [[ "${clause}" == *"Spawn this agent with model="* ]]; then
    assert_fail "T062 NFR-2 tripwire — loud-fail clause contains Spawn success marker — silent-fallback regression!"
  else
    assert_pass "T062 NFR-2 — loud-fail clause carries ONLY the error shape (no Spawn success marker)"
  fi
fi

# --- T063: backward-compat-no-model (NFR-5 byte-identical) ---
# A teammate step without `model:` MUST emit an empty clause — byte-identical
# to wheel's pre-FR-B behavior. Any non-empty clause is a regression.
echo ""
echo "--- T063: backward-compat-no-model ---"
workflow=$(cat "${FIXTURES}/backward-compat-no-model.json")
model=$(extract_model_for_agent "${workflow}" "legacy-step")
if [[ -n "${model}" ]]; then
  assert_fail "fixture regression — expected .model empty/absent, got '${model}'"
else
  clause=$("${HELPER}" model-clause legacy-step "${model}")
  if [[ -z "${clause}" ]]; then
    assert_pass "T063 — absent model field produces empty clause (NFR-5 byte-identical)"
  else
    assert_fail "T063 NFR-5 regression — absent-model step produced non-empty clause: '${clause}'"
  fi
fi

# --- Summary ---
echo ""
echo "Results: ${pass} pass, ${fail} fail"
[[ "${fail}" -eq 0 ]]
