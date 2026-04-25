#!/usr/bin/env bash
# FR-B1 / FR-B2 / FR-B3 — Unit tests for the model-threading helper in
# plugin-wheel/scripts/dispatch/dispatch-agent-step.sh.
#
# Covers:
#   - Absent `model:` field → JSON fragment {"model": null} (I-M1, NFR-5).
#   - Present tier → JSON fragment {"model": "<concrete-id>"}.
#   - Present malformed id → exit 1, stderr carries BOTH the resolve-model.sh
#     prefix AND the step-context wrapper "wheel: model resolution failed for
#     step '<name>': ..." (I-M2, FR-B2 loud-fail).
#   - Step name propagation: the wrapper carries .name or .id when the step
#     omits one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${PLUGIN_DIR}/scripts/dispatch/dispatch-agent-step.sh"

RESOLVE_PREFIX="wheel: model resolve failed"
STEP_PREFIX="wheel: model resolution failed for step"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- Case 1: absent model → {"model": null} (I-M1 byte-identical default) ---
step='{"id":"s1","name":"classify","type":"agent"}'
out=$("${HELPER}" "${step}")
got=$(printf '%s' "${out}" | jq -r '.model')
if [[ "${got}" == "null" ]]; then
  assert_pass "absent model field → JSON fragment with model=null"
else
  assert_fail "absent model should yield null — got '${got}'"
fi

# --- Case 2: model=haiku → resolved to concrete claude-haiku-* id ---
step='{"id":"s1","name":"classify","type":"agent","model":"haiku"}'
out=$("${HELPER}" "${step}")
got=$(printf '%s' "${out}" | jq -r '.model')
if [[ "${got}" =~ ^claude-haiku- ]]; then
  assert_pass "tier haiku resolves through helper to claude-haiku-* (${got})"
else
  assert_fail "tier haiku did not resolve — got '${got}'"
fi

# --- Case 3: model=opus → resolved to concrete claude-opus-* id ---
step='{"id":"s1","name":"reason","type":"agent","model":"opus"}'
out=$("${HELPER}" "${step}")
got=$(printf '%s' "${out}" | jq -r '.model')
if [[ "${got}" =~ ^claude-opus- ]]; then
  assert_pass "tier opus resolves through helper to claude-opus-* (${got})"
else
  assert_fail "tier opus did not resolve — got '${got}'"
fi

# --- Case 4: explicit id → echoed through ---
explicit_id="claude-haiku-4-5-20251001"
step=$(jq -nc --arg m "${explicit_id}" '{id:"s1",name:"c",type:"agent",model:$m}')
out=$("${HELPER}" "${step}")
got=$(printf '%s' "${out}" | jq -r '.model')
if [[ "${got}" == "${explicit_id}" ]]; then
  assert_pass "explicit id passes through unchanged"
else
  assert_fail "explicit id should pass through — expected '${explicit_id}' got '${got}'"
fi

# --- Case 5: malformed id → exit 1 + BOTH loud prefixes (FR-B2) ---
step='{"id":"s1","name":"broken-step","type":"agent","model":"gpt-4"}'
if stderr=$("${HELPER}" "${step}" 2>&1 1>/dev/null); then
  assert_fail "malformed id should exit 1 but exited 0"
else
  if [[ "${stderr}" == *"${RESOLVE_PREFIX}"* ]] && [[ "${stderr}" == *"${STEP_PREFIX} 'broken-step'"* ]]; then
    assert_pass "malformed id exits 1 with BOTH loud prefixes (FR-B2)"
  else
    assert_fail "malformed id stderr missing prefixes — got '${stderr}'"
  fi
fi

# --- Case 6: step without name → falls back to id in error msg ---
step='{"id":"fallback-id","type":"agent","model":"bogus"}'
if stderr=$("${HELPER}" "${step}" 2>&1 1>/dev/null); then
  assert_fail "bogus tier on named step should exit 1 but exited 0"
else
  if [[ "${stderr}" == *"${STEP_PREFIX} 'fallback-id'"* ]]; then
    assert_pass "step-context error falls back to .id when .name absent"
  else
    assert_fail "step-context error should cite .id='fallback-id' — got '${stderr}'"
  fi
fi

# --- Case 7: step without name or id → "<unnamed>" placeholder ---
step='{"type":"agent","model":"bogus"}'
if stderr=$("${HELPER}" "${step}" 2>&1 1>/dev/null); then
  assert_fail "anonymous step with bogus tier should exit 1 but exited 0"
else
  if [[ "${stderr}" == *"${STEP_PREFIX} '<unnamed>'"* ]]; then
    assert_pass "anonymous step uses '<unnamed>' placeholder in loud error"
  else
    assert_fail "anonymous step should carry '<unnamed>' placeholder — got '${stderr}'"
  fi
fi

# --- Case 8: missing argument → exit 1 with helper-owned error ---
if stderr=$("${HELPER}" 2>&1 1>/dev/null); then
  assert_fail "no-arg invocation should exit with non-zero"
else
  assert_pass "no-arg invocation exits non-zero (helper CLI contract)"
fi

# --- Case 9: explicit `model` subcommand produces the same shape ---
# Theme A's extension added subcommand dispatch to the shared file. The
# legacy single-arg form routes to `dispatch_agent_step_model` for
# back-compat; the explicit `model` subcommand MUST produce identical output.
step='{"id":"s1","name":"classify","type":"agent","model":"haiku"}'
legacy_out=$("${HELPER}" "${step}")
explicit_out=$("${HELPER}" model "${step}")
if [[ "${legacy_out}" == "${explicit_out}" ]]; then
  assert_pass "legacy single-arg form equals explicit 'model' subcommand (back-compat)"
else
  assert_fail "legacy vs 'model' subcommand drift — legacy='${legacy_out}' explicit='${explicit_out}'"
fi

# --- Summary ---
echo ""
echo "Results: ${pass} pass, ${fail} fail"
[[ "${fail}" -eq 0 ]]
