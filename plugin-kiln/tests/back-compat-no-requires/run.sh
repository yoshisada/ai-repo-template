#!/usr/bin/env bash
# T052 — back-compat-no-requires fixture (NFR-F-5 + R-F-3 / EC-4 coverage).
#
# Validates: a workflow JSON that does NOT declare `requires_plugins` and
# whose agent instructions contain NO `${WHEEL_PLUGIN_<name>}` or
# `${WORKFLOW_PLUGIN_DIR}` tokens MUST behave byte-identically pre/post-PRD:
#
#   1. Pre-flight resolver `resolve_workflow_dependencies` exits 0 with no
#      stderr output for a no-`requires_plugins` workflow (I-V-3).
#   2. Preprocessor `template_workflow_json` exits 0 and produces a
#      JSON payload byte-identical to the input (I-P-1: only agent `instruction`
#      fields are preprocessed; command-step `command` fields and all other
#      fields pass through unchanged; this fixture's agent instruction
#      contains no plugin-path tokens, only generic `${files[@]}`).
#   3. The narrowed tripwire (FR-F4-5) does NOT fire on instruction text
#      containing generic `${VAR}` syntax (e.g. `${files[@]}`, `${#files[@]}`).
#      This is the EC-4 / R-F-3 regression guard.
#   4. Generic `${VAR}` survives byte-identical post-preprocess.
#
# What this fixture does NOT cover (by design — separate fixtures own these):
#   - Command-step `command` field substitution (intentionally NOT done by the
#     preprocessor; happens at command-execution time via real env vars).
#   - End-to-end `/wheel:wheel-run` activation of an unchanged workflow
#     (covered by the existing wheel-test suite over workflows/tests/).
#   - Cross-plugin `${WHEEL_PLUGIN_*}` resolution (covered by the resolver
#     fixtures owned by impl-registry-resolver).
#
# Strategy:
#   This fixture exercises the post-PRD wheel runtime libraries directly
#   (source + invoke functions). It does NOT spin up `claude --print` because
#   the contract under test is purely shell-layer: registry build + resolver
#   + preprocessor are all bash. End-to-end workflow-activation back-compat
#   is verified by the pre-existing wheel-test suite running every workflow
#   under workflows/tests/ that does NOT declare `requires_plugins`.
#
# Pre-runtime mode:
#   When the runtime libs (plugin-wheel/lib/registry.sh, resolve.sh,
#   preprocess.sh) are not yet in place, this script exits 2 with a clear
#   "RUNTIME NOT READY" message. Phase 5 atomic commit lifts that gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FIXTURE_JSON="${SCRIPT_DIR}/fixtures/no-requires.json"
EXPECTED_INSTR="${SCRIPT_DIR}/baselines/templated-instruction.expected.txt"

REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"
RESOLVE_LIB="${REPO_ROOT}/plugin-wheel/lib/resolve.sh"
PREPROCESS_LIB="${REPO_ROOT}/plugin-wheel/lib/preprocess.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- 0. Static fixture sanity (always runnable, even pre-runtime) -----------

if [[ ! -f "$FIXTURE_JSON" ]]; then
  echo "FAIL: fixture JSON missing at $FIXTURE_JSON" >&2
  exit 1
fi
if ! jq -e . "$FIXTURE_JSON" >/dev/null 2>&1; then
  echo "FAIL: fixture JSON is not valid JSON" >&2
  exit 1
fi
# Fixture must NOT declare requires_plugins (it's the back-compat case).
if jq -e 'has("requires_plugins")' "$FIXTURE_JSON" >/dev/null 2>&1; then
  echo "FAIL: fixture declares requires_plugins — defeats the purpose of the back-compat test" >&2
  exit 1
fi
# Fixture MUST contain ${files[@]} (generic VAR) and ${WORKFLOW_PLUGIN_DIR}
# tokens in the documented places.
if ! grep -qF '${files[@]}' "$FIXTURE_JSON"; then
  echo "FAIL: fixture lost its generic \${VAR} (\${files[@]}) — EC-4 coverage broken" >&2
  exit 1
fi
if ! grep -qF '${WORKFLOW_PLUGIN_DIR}' "$FIXTURE_JSON"; then
  echo "FAIL: fixture lost its legacy \${WORKFLOW_PLUGIN_DIR} reference — FR-F4-3 coverage broken (in command step, NOT preprocessed but ensures legacy env-var path is exercised at command-dispatch time)" >&2
  exit 1
fi
# Agent step instruction MUST NOT contain any plugin-path tokens (this is
# the no-requires case — agent has only generic ${files[@]} VARs).
if jq -r '.steps[] | select(.type=="agent") | .instruction' "$FIXTURE_JSON" \
   | grep -qE '\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)'; then
  echo "FAIL: fixture's agent instruction contains plugin-path tokens — defeats no-requires invariant" >&2
  exit 1
fi
assert_pass "static fixture sanity (no requires_plugins, has \${files[@]} + legacy \${WORKFLOW_PLUGIN_DIR} in command step, agent instruction has no plugin-path tokens)"

# --- 1. Runtime gate ---------------------------------------------------------

if [[ ! -f "$RESOLVE_LIB" || ! -f "$PREPROCESS_LIB" || ! -f "$REGISTRY_LIB" ]]; then
  cat >&2 <<EOF
RUNTIME NOT READY: plugin-wheel/lib/{registry,resolve,preprocess}.sh missing.
This fixture is scaffolded ahead of the Phase 3 / Phase 4 implementer commits
per the team's atomic-landing protocol (NFR-F-7). Once impl-registry-resolver
and impl-preprocessor land their work, re-run this script to verify NFR-F-5.

Static portion passed (1/1). Skipping runtime portion (exit 2).
EOF
  exit 2
fi

# --- 2. Resolver: empty stderr + exit 0 for no-requires workflow ------------

# shellcheck disable=SC1090
source "$REGISTRY_LIB"
# shellcheck disable=SC1090
source "$RESOLVE_LIB"
# shellcheck disable=SC1090
source "$PREPROCESS_LIB"

REGISTRY_JSON=$(build_session_registry)
WORKFLOW_JSON=$(jq -c . "$FIXTURE_JSON")

set +e
RESOLVER_STDERR=$(resolve_workflow_dependencies "$WORKFLOW_JSON" "$REGISTRY_JSON" 2>&1 >/dev/null)
RESOLVER_EXIT=$?
set -e

if [[ $RESOLVER_EXIT -ne 0 ]]; then
  assert_fail "resolver should exit 0 for no-requires workflow (got $RESOLVER_EXIT; stderr: $RESOLVER_STDERR)"
elif [[ -n "$RESOLVER_STDERR" ]]; then
  assert_fail "resolver should produce no stderr for no-requires workflow (got: $RESOLVER_STDERR)"
else
  assert_pass "resolver exits 0 silently for no-requires workflow (I-V-3)"
fi

# --- 3. Preprocessor: byte-identical output, generic ${VAR} preserved ------

# Calling plugin dir is plugin-shelf for this fixture (the workflow's command
# step references shelf-internal scripts via WORKFLOW_PLUGIN_DIR — which the
# preprocessor leaves untouched per I-P-1; only agent instructions are
# preprocessed).
CALLING_PLUGIN_DIR="${REPO_ROOT}/plugin-shelf"

set +e
TEMPLATED_JSON=$(template_workflow_json "$WORKFLOW_JSON" "$REGISTRY_JSON" "$CALLING_PLUGIN_DIR" 2>/tmp/preprocess-err.$$)
PREPROCESS_EXIT=$?
PREPROCESS_STDERR=$(cat /tmp/preprocess-err.$$ 2>/dev/null || true)
rm -f /tmp/preprocess-err.$$
set -e

if [[ $PREPROCESS_EXIT -ne 0 ]]; then
  assert_fail "preprocessor should exit 0 (got $PREPROCESS_EXIT; stderr: $PREPROCESS_STDERR)"
fi

# 3.a Byte-identity: this workflow has no plugin-path tokens in agent
# instructions, so the templated JSON MUST be byte-identical to the input
# JSON (NFR-F-5 strongest form — the byte-identity hinges on agent
# instructions having no substitution sites).
if [[ "$TEMPLATED_JSON" == "$WORKFLOW_JSON" ]]; then
  assert_pass "templated JSON byte-identical to input JSON (NFR-F-5)"
else
  assert_fail "templated JSON differs from input — back-compat regression"
  diff <(printf '%s' "$WORKFLOW_JSON" | jq .) <(printf '%s' "$TEMPLATED_JSON" | jq .) >&2 || true
fi

# 3.b Agent instruction byte-identical (sub-assertion of 3.a, but explicit
# for failure-message clarity).
ACTUAL_INSTR=$(jq -r '.steps[] | select(.id=="agent-with-generic-var-syntax") | .instruction' <<<"$TEMPLATED_JSON")
EXPECTED_INSTR_BODY=$(cat "$EXPECTED_INSTR")
EXPECTED_INSTR_BODY="${EXPECTED_INSTR_BODY%$'\n'}"
if [[ "$ACTUAL_INSTR" == "$EXPECTED_INSTR_BODY" ]]; then
  assert_pass "agent instruction byte-identical post-preprocess (NFR-F-5; \${files[@]} preserved)"
else
  assert_fail "agent instruction not byte-identical post-preprocess"
  diff <(printf '%s' "$EXPECTED_INSTR_BODY") <(printf '%s' "$ACTUAL_INSTR") >&2 || true
fi

# 3.c Tripwire negative: no ${WHEEL_PLUGIN_ or ${WORKFLOW_PLUGIN_DIR substring
# remains in any agent instruction (defense-in-depth).
if jq -r '.steps[] | select(.type=="agent") | .instruction' <<<"$TEMPLATED_JSON" \
   | grep -qE '\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)'; then
  assert_fail "templated agent instruction contains plugin-path tokens — preprocessor failed silently"
else
  assert_pass "templated agent instruction contains zero plugin-path tokens (FR-F4-6)"
fi

# 3.d Generic ${VAR} (${files[@]}) is preserved.
if jq -r '.steps[] | select(.type=="agent") | .instruction' <<<"$TEMPLATED_JSON" \
   | grep -qF '${files[@]}'; then
  assert_pass "generic \${VAR} (\${files[@]}) preserved post-preprocess (R-F-3 / EC-4)"
else
  assert_fail "generic \${files[@]} disappeared post-preprocess — tripwire over-fires"
fi

# 3.e Command-step command field unchanged: ${WORKFLOW_PLUGIN_DIR} stays
# literal in the JSON (preprocessor scope is agent instructions only per
# I-P-1; command substitution happens at command-execution time via real
# exported env var).
ACTUAL_CMD=$(jq -r '.steps[] | select(.id=="in-plugin-script-via-legacy-token") | .command' <<<"$TEMPLATED_JSON")
EXPECTED_CMD='bash "${WORKFLOW_PLUGIN_DIR}/scripts/echo-self.sh"'
if [[ "$ACTUAL_CMD" == "$EXPECTED_CMD" ]]; then
  assert_pass "command-step .command preserves \${WORKFLOW_PLUGIN_DIR} literal (I-P-1: command fields not preprocessed)"
else
  assert_fail "command-step .command unexpectedly modified by preprocessor"
  echo "  expected: $EXPECTED_CMD" >&2
  echo "  actual:   $ACTUAL_CMD" >&2
fi

# --- Summary ---------------------------------------------------------------
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
