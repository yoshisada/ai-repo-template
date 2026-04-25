#!/usr/bin/env bash
# T045 / SC-005 — kiln-fix resolver-spawn skill test (simplified 2026-04-25).
#
# Contract per spec.md User Story 3 + SC-005:
#   "A kiln skill (e.g. /kiln:kiln-fix) spawns kiln:debugger via the resolver
#    primitive — without referencing a central registry."
#
# Asserted invariants (post-registry-deletion):
#   1. /kiln:kiln-fix SKILL.md text references the resolver path AND the
#      plugin-prefixed name kiln:debugger (FR-A5 documented path).
#   2. resolve.sh kiln:debugger → source=passthrough, subagent_type=kiln:debugger
#      (the harness's filesystem-discovered registration handles the spawn —
#      no central registry consulted).
#
# The previous registry-tampering inversion test (was: "swap registry entry,
# verify resolver returns wrong path") was retired alongside the registry
# deletion — there's no central registry to tamper with, and plugin-prefixed
# passthrough is the simple, correct mechanism by design.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RESOLVE="${REPO_ROOT}/plugin-wheel/scripts/agents/resolve.sh"
KILN_FIX_SKILL="${REPO_ROOT}/plugin-kiln/skills/kiln-fix/SKILL.md"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# --- 1. SKILL.md documents the resolver-spawn path (FR-A5) with plugin-prefixed name ---
if grep -q 'plugin-wheel/scripts/agents/resolve.sh' "$KILN_FIX_SKILL" \
   && grep -q 'kiln:debugger' "$KILN_FIX_SKILL"; then
  assert_pass "SKILL.md references the resolver + plugin-prefixed kiln:debugger (FR-A5)"
else
  assert_fail "SKILL.md missing resolver + kiln:debugger references"
fi

# --- 2. Happy path: resolver passes through plugin-prefixed kiln:debugger ---
out=$("$RESOLVE" kiln:debugger)
subagent_type=$(jq -r '.subagent_type' <<<"$out")
source_val=$(jq -r '.source' <<<"$out")
if [[ "$subagent_type" == "kiln:debugger" && "$source_val" == "passthrough" ]]; then
  assert_pass "resolver(kiln:debugger) → subagent_type=kiln:debugger, source=passthrough"
else
  assert_fail "resolver(kiln:debugger): got subagent_type=$subagent_type source=$source_val"
fi

# --- Summary ---
echo
echo "--- Results: ${pass} passed, ${fail} failed ---"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
