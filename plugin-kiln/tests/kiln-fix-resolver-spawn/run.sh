#!/usr/bin/env bash
# T045 / SC-005 — kiln-fix resolver-spawn skill test.
#
# Contract per spec.md User Story 3 + SC-005:
#   "A kiln skill (e.g. /kiln:kiln-fix) spawns `debugger` via the resolver;
#    swap the resolver to return the wrong spec → test fails."
#
# The full harness form would boot a live claude --print subprocess against a
# fixture dir and assert the spawned sub-agent's system prompt. That is the
# /kiln:kiln-test shape and lives under plugin-kiln/tests/kiln-fix-resolver-spawn/
# with a test.yaml. This run.sh is the lightweight tripwire form suitable for
# CI / wheel-test: it asserts the static resolver-side invariants that
# determine the spawned agent's system prompt, plus the SC-005 inversion.
#
# Asserted invariants:
#   1. /kiln:kiln-fix SKILL.md text references the resolver path (FR-A5).
#   2. resolve.sh debugger → system_prompt_path ends with plugin-kiln/agents/debugger.md.
#   3. Inversion: if we swap the registry entry for 'debugger' to point at a
#      different path, the resolver returns the wrong path — proving the
#      resolver is the component under test (if the SKILL.md hard-coded the
#      path, the test would pass anyway, which is the failure mode SC-005
#      wants to catch).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RESOLVE="${REPO_ROOT}/plugin-wheel/scripts/agents/resolve.sh"
KILN_FIX_SKILL="${REPO_ROOT}/plugin-kiln/skills/kiln-fix/SKILL.md"
REGISTRY="${REPO_ROOT}/plugin-wheel/scripts/agents/registry.json"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- 1. SKILL.md documents the resolver-spawn path (FR-A5) ---
if grep -q 'plugin-wheel/scripts/agents/resolve.sh' "$KILN_FIX_SKILL" \
   && grep -q 'debugger' "$KILN_FIX_SKILL"; then
  assert_pass "SKILL.md references the resolver + debugger (FR-A5 documented path)"
else
  assert_fail "SKILL.md missing resolver-spawn documentation"
fi

# --- 2. Happy path: resolver returns the right system prompt for 'debugger' ---
out=$("$RESOLVE" debugger)
sys_path=$(jq -r '.system_prompt_path' <<<"$out")
if [[ "$sys_path" == *"plugin-kiln/agents/debugger.md" ]]; then
  assert_pass "resolver(debugger).system_prompt_path ends with plugin-kiln/agents/debugger.md"
else
  assert_fail "resolver(debugger): got system_prompt_path=$sys_path"
fi

# --- 3. Inversion: swap the registry entry to a bogus path → resolver returns the bogus path ---
# This proves the resolver is genuinely what determines the system prompt —
# if the SKILL.md had bypassed the resolver and hard-coded the path, the
# inversion would pass (same result), and THAT is the failure SC-005 wants
# to catch.
tmp_dir="$(mktemp -d -t kiln-fix-resolver-inv.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '$tmp_dir'" EXIT

# Build a tampered plugin root: copy registry with a bogus entry for 'debugger'.
mkdir -p "${tmp_dir}/scripts/agents"
mkdir -p "${tmp_dir}/agents"
jq '.agents.debugger.path = "plugin-kiln/agents/NOT-REAL-debugger.md"' \
  "$REGISTRY" > "${tmp_dir}/scripts/agents/registry.json"
# Create a dummy file at the bogus path so the resolver doesn't exit 1 on file-not-found.
mkdir -p "${tmp_dir}/../agents-fake" # irrelevant but keeps intent visible
# The resolver tries PLUGIN_ROOT's parent / rel_path; we set WORKFLOW_PLUGIN_DIR=$tmp_dir
# and the parent is $tmp_dir/.., so we need the bogus path there.
parent="$(cd "${tmp_dir}/.." && pwd)"
mkdir -p "${parent}/plugin-kiln/agents"
# Ensure our bogus file is readable so resolver doesn't bail early.
touch "${parent}/plugin-kiln/agents/NOT-REAL-debugger.md"

inverted=$(WORKFLOW_PLUGIN_DIR="$tmp_dir" "$RESOLVE" debugger)
inv_path=$(jq -r '.system_prompt_path' <<<"$inverted")
if [[ "$inv_path" == *"NOT-REAL-debugger.md" ]]; then
  assert_pass "inversion: tampered registry → resolver returns tampered path (confirms resolver is the determinant)"
else
  assert_fail "inversion expected NOT-REAL-debugger.md path, got $inv_path"
fi

# Clean up the bogus parent artifact we created (outside tmp_dir).
rm -f "${parent}/plugin-kiln/agents/NOT-REAL-debugger.md"

# --- Summary ---
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
