#!/usr/bin/env bash
# FR-B1 / FR-B2 — Unit tests for `dispatch_agent_step_model_clause` in
# plugin-wheel/scripts/dispatch/dispatch-agent-step.sh.
#
# The clause is spliced into wheel's teammate spawn instruction. Tests cover:
#   - Absent spec → empty stdout (NFR-5 byte-identical).
#   - Tier spec (haiku/sonnet/opus) → success clause with resolved id.
#   - Explicit id spec → success clause with echoed id.
#   - Malformed spec → ACTIVATION ERROR clause (FR-B2 invariant).
#   - The ACTIVATION ERROR clause names the teammate + the spec + the
#     resolver diagnostic (orchestrator needs all three to surface the error).
#   - Helper does NOT emit a silent default-model clause on any failure path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${PLUGIN_DIR}/scripts/dispatch/dispatch-agent-step.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- Case 1: empty spec → empty stdout (NFR-5) ---
out=$("${HELPER}" model-clause some-agent "")
if [[ -z "${out}" ]]; then
  assert_pass "empty spec → empty stdout (NFR-5 byte-identical)"
else
  assert_fail "empty spec should emit nothing — got '${out}'"
fi

# --- Case 2: tier=haiku → success clause with claude-haiku-* id ---
out=$("${HELPER}" model-clause classify haiku)
if [[ "${out}" == *"Spawn this agent with model='claude-haiku-"* ]]; then
  assert_pass "tier haiku emits Spawn-with-model clause naming claude-haiku-*"
else
  assert_fail "tier haiku clause malformed — got '${out}'"
fi
if [[ "${out}" == *"FR-B1"* ]]; then
  assert_pass "tier haiku clause includes the FR-B1 provenance marker"
else
  assert_fail "tier haiku clause missing FR-B1 marker — got '${out}'"
fi

# --- Case 3: tier=sonnet → success clause with claude-sonnet-* id ---
out=$("${HELPER}" model-clause synthesize sonnet)
if [[ "${out}" == *"model='claude-sonnet-"* ]]; then
  assert_pass "tier sonnet resolves in-clause to claude-sonnet-*"
else
  assert_fail "tier sonnet clause malformed — got '${out}'"
fi

# --- Case 4: explicit id → echoed into clause ---
explicit="claude-haiku-4-5-20251001"
out=$("${HELPER}" model-clause fast "${explicit}")
if [[ "${out}" == *"model='${explicit}'"* ]]; then
  assert_pass "explicit id passes through into clause"
else
  assert_fail "explicit id not in clause — got '${out}'"
fi

# --- Case 5: malformed spec → ACTIVATION ERROR clause (FR-B2 loud-fail) ---
out=$("${HELPER}" model-clause broken bogus)
if [[ "${out}" == *"ACTIVATION ERROR"* ]]; then
  assert_pass "malformed spec emits ACTIVATION ERROR clause (FR-B2)"
else
  assert_fail "malformed spec did NOT emit ACTIVATION ERROR — silent-fallback regression! got '${out}'"
fi

# --- Case 6: ACTIVATION ERROR clause names the teammate ---
if [[ "${out}" == *"teammate 'broken'"* ]]; then
  assert_pass "ACTIVATION ERROR clause names the teammate"
else
  assert_fail "ACTIVATION ERROR clause missing teammate name — got '${out}'"
fi

# --- Case 7: ACTIVATION ERROR clause names the spec ---
if [[ "${out}" == *"spec='bogus'"* ]]; then
  assert_pass "ACTIVATION ERROR clause names the offending spec"
else
  assert_fail "ACTIVATION ERROR clause missing spec — got '${out}'"
fi

# --- Case 8: ACTIVATION ERROR clause includes the resolver diagnostic ---
if [[ "${out}" == *"wheel: model resolve failed"* ]]; then
  assert_pass "ACTIVATION ERROR clause includes resolver diagnostic"
else
  assert_fail "ACTIVATION ERROR clause missing resolver diagnostic — got '${out}'"
fi

# --- Case 9: ACTIVATION ERROR clause tells orchestrator to stop ---
if [[ "${out}" == *"Do NOT spawn this agent on default"* ]]; then
  assert_pass "ACTIVATION ERROR clause tells orchestrator to stop"
else
  assert_fail "ACTIVATION ERROR clause missing stop directive — got '${out}'"
fi

# --- Case 10: silent-failure tripwire (NFR-2) — malformed spec MUST NOT
# produce a Spawn-with-model clause that carries a default id. If it does,
# that's the original bug shape returning.
if [[ "${out}" == *"Spawn this agent with model="* ]]; then
  assert_fail "silent-fallback regression — malformed spec produced a Spawn clause! got '${out}'"
else
  assert_pass "NFR-2 tripwire — malformed spec does NOT emit a Spawn-with-model clause"
fi

# --- Summary ---
echo ""
echo "Results: ${pass} pass, ${fail} fail"
[[ "${fail}" -eq 0 ]]
