#!/usr/bin/env bash
# FR-B1 / FR-B2 unit tests for plugin-wheel/scripts/dispatch/resolve-model.sh.
#
# Covers contract §3 "Tests":
#   - resolve-model.sh haiku   → stdout matches ^claude-haiku-
#   - resolve-model.sh sonnet  → stdout matches ^claude-sonnet-
#   - resolve-model.sh opus    → stdout matches ^claude-opus-
#   - resolve-model.sh claude-haiku-4-5-20251001 → echoes input (I-M3)
#   - resolve-model.sh bogus   → exit 1, stderr carries loud-fail fingerprint (I-M2)
#   - resolve-model.sh ""      → exit 1, loud-fail
#   - resolve-model.sh "foo,bar"              → exit 1 (OQ-2: strictly one model per step)
#   - model-defaults.json missing             → exit 1, loud-fail
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVER="${PLUGIN_DIR}/scripts/dispatch/resolve-model.sh"
DEFAULTS="${PLUGIN_DIR}/scripts/dispatch/model-defaults.json"

ERR_PREFIX="wheel: model resolve failed"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- Case 1: tier=haiku resolves to ^claude-haiku- ---
out=$("${RESOLVER}" haiku)
if [[ "${out}" =~ ^claude-haiku- ]]; then
  assert_pass "tier haiku resolves to claude-haiku-* (${out})"
else
  assert_fail "tier haiku did not match ^claude-haiku- — got '${out}'"
fi

# --- Case 2: tier=sonnet resolves to ^claude-sonnet- ---
out=$("${RESOLVER}" sonnet)
if [[ "${out}" =~ ^claude-sonnet- ]]; then
  assert_pass "tier sonnet resolves to claude-sonnet-* (${out})"
else
  assert_fail "tier sonnet did not match ^claude-sonnet- — got '${out}'"
fi

# --- Case 3: tier=opus resolves to ^claude-opus- ---
out=$("${RESOLVER}" opus)
if [[ "${out}" =~ ^claude-opus- ]]; then
  assert_pass "tier opus resolves to claude-opus-* (${out})"
else
  assert_fail "tier opus did not match ^claude-opus- — got '${out}'"
fi

# --- Case 4: explicit id echoes input (I-M3, regex-only admission) ---
explicit="claude-haiku-4-5-20251001"
out=$("${RESOLVER}" "${explicit}")
if [[ "${out}" == "${explicit}" ]]; then
  assert_pass "explicit id echoes input unchanged"
else
  assert_fail "explicit id should echo input — expected '${explicit}' got '${out}'"
fi

# --- Case 5: bogus tier → exit 1 + loud stderr (I-M2 FR-B2 invariant) ---
if stderr=$("${RESOLVER}" bogus 2>&1 1>/dev/null); then
  assert_fail "bogus spec should have exited 1 but exited 0"
else
  if [[ "${stderr}" == *"${ERR_PREFIX}"* ]]; then
    assert_pass "bogus spec exits 1 with loud-fail prefix"
  else
    assert_fail "bogus spec stderr missing loud-fail prefix '${ERR_PREFIX}' — got '${stderr}'"
  fi
fi

# --- Case 6: empty spec → exit 1 + loud stderr ---
if stderr=$("${RESOLVER}" "" 2>&1 1>/dev/null); then
  assert_fail "empty spec should have exited 1 but exited 0"
else
  if [[ "${stderr}" == *"${ERR_PREFIX}"* ]]; then
    assert_pass "empty spec exits 1 with loud-fail prefix"
  else
    assert_fail "empty spec stderr missing loud-fail prefix — got '${stderr}'"
  fi
fi

# --- Case 7: OQ-2 decision — comma-separated fallback list rejected ---
if stderr=$("${RESOLVER}" "haiku,sonnet" 2>&1 1>/dev/null); then
  assert_fail "comma-separated list should have exited 1 (OQ-2: strictly one model per step)"
else
  if [[ "${stderr}" == *"${ERR_PREFIX}"* ]]; then
    assert_pass "comma-separated list exits 1 (OQ-2 strictly-one-model enforced)"
  else
    assert_fail "comma-separated list stderr missing loud-fail prefix — got '${stderr}'"
  fi
fi

# --- Case 8: non-claude explicit id → exit 1 + loud (I-M3 regex guard) ---
if stderr=$("${RESOLVER}" "gpt-4" 2>&1 1>/dev/null); then
  assert_fail "non-claude id should have exited 1"
else
  if [[ "${stderr}" == *"${ERR_PREFIX}"* ]]; then
    assert_pass "non-claude id exits 1 with loud-fail prefix"
  else
    assert_fail "non-claude id stderr missing loud-fail prefix — got '${stderr}'"
  fi
fi

# --- Case 9: missing model-defaults.json → exit 1 + loud ---
# Use a shim that points at a bad defaults path by temporarily moving the file.
backup="${DEFAULTS}.bak-test-$$"
mv "${DEFAULTS}" "${backup}"
trap 'mv "${backup}" "${DEFAULTS}" 2>/dev/null || true' EXIT
if stderr=$("${RESOLVER}" haiku 2>&1 1>/dev/null); then
  assert_fail "missing model-defaults.json should have exited 1"
else
  if [[ "${stderr}" == *"${ERR_PREFIX}"* ]]; then
    assert_pass "missing defaults file exits 1 with loud-fail prefix"
  else
    assert_fail "missing defaults file stderr missing loud-fail prefix — got '${stderr}'"
  fi
fi
mv "${backup}" "${DEFAULTS}"
trap - EXIT

# --- Summary ---
echo ""
echo "Results: ${pass} pass, ${fail} fail"
[[ "${fail}" -eq 0 ]]
