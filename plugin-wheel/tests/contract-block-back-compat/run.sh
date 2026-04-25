#!/usr/bin/env bash
# T024 — contract-block-back-compat fixture.
#
# specs/wheel-typed-schema-locality acceptance scenarios covered:
#   User Story 2 — Acceptance Scenario 4 (legacy step → byte-identical body).
#
# FRs covered:
#   FR-H2-4 (NEITHER inputs: NOR output_schema: → byte-identical legacy
#            reminder body)
# NFR coverage:
#   NFR-H-3 (strict back-compat — byte snapshot)
#   NFR-H-2 (mutation tripwire — flip back-compat path to emit contract block;
#            assert snapshot diff fails)
#
# Strategy: this fixture pins the EXACT post-PRD body that the Stop-hook
# emits for a legacy step (no inputs:/no output_schema:). The pre-PRD baseline
# was: `Step '<id>' is in progress. Write your output to: <path>`. After this
# PRD's surfacing logic, an empty contract block + reminder concatenation must
# resolve to byte-identical text — `${_reminder}` only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"

source "${WHEEL_LIB_DIR}/preprocess.sh"
source "${WHEEL_LIB_DIR}/context.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# -----------------------------------------------------------------------------
# Pre-PRD snapshot (captured from dispatch.sh line ~683 prior to PRD landing —
# the format string is `"Step '${step_id}' is in progress. Write your output
# to: ${output_key}"`). NFR-H-3 byte-identity locks this exact string.
# -----------------------------------------------------------------------------
PRE_PRD_BODY="Step 'legacy-step' is in progress. Write your output to: /tmp/legacy-out.json"

# Compose the post-PRD body using the SAME logic dispatch.sh now uses:
#   _contract_block=$(context_compose_contract_block ...)
#   _reminder="Step '${step_id}' is in progress. Write your output to: ${output_key}"
#   _body= [contract_block + \n\n + reminder, OR reminder alone if block empty]
LEGACY_STEP='{"id":"legacy-step","instruction":"Just an instruction"}'
CONTRACT_BLOCK=$(context_compose_contract_block "$LEGACY_STEP" "{}")
REMINDER="Step 'legacy-step' is in progress. Write your output to: /tmp/legacy-out.json"
if [[ -n "$CONTRACT_BLOCK" ]]; then
  POST_PRD_BODY="${CONTRACT_BLOCK}"$'\n\n'"${REMINDER}"
else
  POST_PRD_BODY="$REMINDER"
fi

# T1: contract block is empty for legacy step (FR-H2-4 path).
if [[ -z "$CONTRACT_BLOCK" ]]; then
  assert_pass "T1 — FR-H2-4: contract block empty for legacy step (no inputs/no output_schema)"
else
  assert_fail "T1 — contract block leaked: '$CONTRACT_BLOCK'"
fi

# T2: post-PRD body byte-identical to pre-PRD baseline (NFR-H-3).
if [[ "$POST_PRD_BODY" == "$PRE_PRD_BODY" ]]; then
  assert_pass "T2 — NFR-H-3: post-PRD body byte-identical to pre-PRD baseline"
else
  assert_fail "T2 — body diverged:"$'\n'"--pre--"$'\n'"$PRE_PRD_BODY"$'\n'"--post--"$'\n'"$POST_PRD_BODY"
fi

# T3: hexdump-level byte diff — guards against invisible differences (CR vs
# LF, trailing spaces, BOM, etc.).
PRE_HEX=$(printf '%s' "$PRE_PRD_BODY" | od -c)
POST_HEX=$(printf '%s' "$POST_PRD_BODY" | od -c)
if [[ "$PRE_HEX" == "$POST_HEX" ]]; then
  assert_pass "T3 — NFR-H-3: byte-level (od -c) match"
else
  assert_fail "T3 — byte-level diff:"$'\n'"--pre--"$'\n'"$PRE_HEX"$'\n'"--post--"$'\n'"$POST_HEX"
fi

# T4: NEITHER inputs nor output_schema, no instruction either — still empty.
BARE='{"id":"bare"}'
out=$(context_compose_contract_block "$BARE" "{}")
if [[ -z "$out" ]]; then
  assert_pass "T4 — bare step (no fields) → empty contract block"
else
  assert_fail "T4 — bare step leaked block: '$out'"
fi

# T5: legacy step with `context_from:` (PRE-PRD multi-step pattern) — still
# empty. The dispatch loop's reminder is unchanged; context_from drives
# context_build, not the Stop-hook surfacing.
LEGACY_CTX='{"id":"ctx","instruction":"Use deps","context_from":["upstream"]}'
out=$(context_compose_contract_block "$LEGACY_CTX" "{}")
if [[ -z "$out" ]]; then
  assert_pass "T5 — legacy step with context_from: → empty contract block (NFR-H-3)"
else
  assert_fail "T5 — context_from leaked into contract block: '$out'"
fi

# -----------------------------------------------------------------------------
# T6: NFR-H-2 mutation tripwire. Flip the back-compat path to emit the
# contract block on legacy steps, then assert the snapshot diff fails.
#
# Mutation: replace `if [[ "$has_inputs" == "no" && "$has_output_schema" ==
# "no" ]]; then return 0; fi` with a no-op that lets execution fall through.
# A regression to "always emit" would ship green without this tripwire.
# -----------------------------------------------------------------------------
TMP=$(mktemp -d)
MUTATED="$TMP/context_mutated.sh"
cp "${WHEEL_LIB_DIR}/context.sh" "$MUTATED"
python3 -c "
import re
src = open('$MUTATED').read()
# Replace the FR-H2-4 back-compat early-return with a comment so legacy steps
# now trigger the surfacing path. Search by anchor text.
patched = src.replace(
  'if [[ \"\$has_inputs\" == \"no\" && \"\$has_output_schema\" == \"no\" ]]; then\n    return 0\n  fi',
  '# NFR-H-2 MUTATION: back-compat early-return removed'
)
open('$MUTATED', 'w').write(patched)
"

# Sub-shell with mutated context.sh.
mutated_block=$(
  source "${WHEEL_LIB_DIR}/preprocess.sh"
  source "$MUTATED"
  context_compose_contract_block "$LEGACY_STEP" "{}"
)

# In a healthy mutation, the mutated block is NON-empty (contract block
# emitted on legacy step) — meaning the snapshot diff fails.
if [[ -n "$mutated_block" ]]; then
  # Even mutated, the only declarations the legacy step has are .instruction —
  # so the mutated path emits the Step Instruction section.
  assert_pass "T6 — NFR-H-2 tripwire: removing the back-compat early-return causes contract block to leak (regression would diverge from snapshot)"
else
  assert_fail "T6 — mutation didn't take; mutated_block still empty"
fi

# Sanity: real (unmutated) composer still empty.
real_block=$(context_compose_contract_block "$LEGACY_STEP" "{}")
if [[ -z "$real_block" ]]; then
  assert_pass "T7 — NFR-H-2 control: real composer still empty for legacy step"
else
  assert_fail "T7 — real composer regressed: '$real_block'"
fi

rm -rf "$TMP"

echo
echo "==> contract-block-back-compat: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
