#!/usr/bin/env bash
# T026 — contract-block-partial fixture.
#
# specs/wheel-typed-schema-locality FR coverage:
#   FR-H2-6 omission rule — only declared sections appear.
#
# Step shape: ONLY `output_schema:` declared (no `inputs:`, no `instruction:`).
# Asserts: `## Required Output Schema` present, other sections ABSENT.
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

# Step with ONLY output_schema: declared.
STEP_ONLY_SCHEMA='{"id":"only-schema","output_schema":{"k":"$.k"}}'
OUT=$(context_compose_contract_block "$STEP_ONLY_SCHEMA" "{}")

if [[ "$OUT" == *"## Required Output Schema"* ]]; then
  assert_pass "T1 — only output_schema declared: ## Required Output Schema PRESENT"
else
  assert_fail "T1 — Required Output Schema missing"
fi
if [[ "$OUT" != *"## Resolved Inputs"* ]]; then
  assert_pass "T2 — FR-H2-6: ## Resolved Inputs ABSENT (no inputs declared)"
else
  assert_fail "T2 — ## Resolved Inputs leaked"
fi
if [[ "$OUT" != *"## Step Instruction"* ]]; then
  assert_pass "T3 — FR-H2-6: ## Step Instruction ABSENT (no instruction declared)"
else
  assert_fail "T3 — ## Step Instruction leaked"
fi

# Step with ONLY instruction: + output_schema: (no inputs:).
STEP_INSTR_SCHEMA='{"id":"instr","instruction":"Just do the thing.","output_schema":{"k":"$.k"}}'
OUT2=$(context_compose_contract_block "$STEP_INSTR_SCHEMA" "{}")

if [[ "$OUT2" == *"## Step Instruction"* && "$OUT2" == *"Just do the thing."* ]]; then
  assert_pass "T4 — instruction+output_schema: instruction surfaced (FR-H2-2)"
else
  assert_fail "T4 — instruction missing in instr+schema case; got: $OUT2"
fi
if [[ "$OUT2" != *"## Resolved Inputs"* ]]; then
  assert_pass "T5 — instruction+output_schema: ## Resolved Inputs ABSENT"
else
  assert_fail "T5 — Resolved Inputs leaked into instr+schema case"
fi

# Step with ONLY inputs: + instruction: (no output_schema:).
STEP_INPUTS='{"id":"inputs","inputs":{"X":"$.x"},"instruction":"Use {{X}}."}'
RESOLVED='{"X":"value-x"}'
OUT3=$(context_compose_contract_block "$STEP_INPUTS" "$RESOLVED")

if [[ "$OUT3" == *"## Resolved Inputs"* && "$OUT3" == *"## Step Instruction"* ]]; then
  assert_pass "T6 — inputs+instruction: both sections surfaced"
else
  assert_fail "T6 — inputs+instruction sections missing; got: $OUT3"
fi
if [[ "$OUT3" != *"## Required Output Schema"* ]]; then
  assert_pass "T7 — inputs+instruction: ## Required Output Schema ABSENT"
else
  assert_fail "T7 — Required Output Schema leaked into inputs-only case"
fi

# Spec edge case: empty output_schema {} treated as absent.
STEP_EMPTY_SCHEMA='{"id":"empty","inputs":{"X":"$.x"},"instruction":"x","output_schema":{}}'
OUT4=$(context_compose_contract_block "$STEP_EMPTY_SCHEMA" "$RESOLVED")
if [[ "$OUT4" != *"## Required Output Schema"* ]]; then
  assert_pass "T8 — empty output_schema {} treated as absent (FR-H2-6 / spec edge case)"
else
  assert_fail "T8 — empty schema rendered as a section"
fi

echo
echo "==> contract-block-partial: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
