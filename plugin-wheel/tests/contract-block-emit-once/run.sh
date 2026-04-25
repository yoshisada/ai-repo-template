#!/usr/bin/env bash
# T023 — contract-block-emit-once fixture.
#
# specs/wheel-typed-schema-locality acceptance scenarios covered:
#   User Story 2 — Acceptance Scenario 5 (re-entry suppression).
#
# FRs covered:
#   FR-H2-5 / OQ-H-1 — emit contract block exactly ONCE per step entry. Second
#   tick on the same step (e.g. after Theme H1 violation + re-write) → block
#   suppressed; only "Step in progress" reminder remains.
# NFR coverage:
#   NFR-H-2 mutation tripwire — flip contract_emitted to never-set; assert
#   tick 2 re-emits.
#
# Strategy: simulate dispatch.sh's surfacing branch end-to-end at the BODY
# composition level. Set up a state file, exercise context_compose_contract_block
# + state_get/set_contract_emitted, and verify the gating logic.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"

source "${WHEEL_LIB_DIR}/preprocess.sh"
source "${WHEEL_LIB_DIR}/context.sh"
source "${WHEEL_LIB_DIR}/state.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d)
SF="$TMP/state.json"

# Seed state file: one step, working, contract_emitted absent (default false).
cat > "$SF" <<'EOF'
{
  "name": "emit-once-fixture",
  "cursor": 0,
  "updated_at": "2020-01-01T00:00:00.000Z",
  "steps": [
    {
      "id": "typed-step",
      "type": "agent",
      "status": "working",
      "started_at": null,
      "completed_at": null,
      "output": null,
      "command_log": [],
      "agents": {},
      "loop_iteration": 0,
      "resolved_inputs": {"FOO": "bar"}
    }
  ]
}
EOF

STEP=$(cat <<'EOF'
{"id":"typed-step","type":"agent","inputs":{"FOO":"$.steps.s1.output.foo"},"instruction":"Use {{FOO}}.","output_schema":{"out_key":"$.out_key"},"output":"/tmp/typed-out.json"}
EOF
)
REMINDER="Step 'typed-step' is in progress. Write your output to: /tmp/typed-out.json"

# -----------------------------------------------------------------------------
# Helper: simulate dispatch.sh's stop-branch reminder body composition.
# Mirrors the production logic exactly.
# -----------------------------------------------------------------------------
compose_reminder_body() {
  local sf="$1"
  local step="$2"
  local step_idx="$3"
  local rem="$4"

  local emitted contract_block resolved_persisted body
  emitted=$(state_get_contract_emitted "$sf" "$step_idx")
  contract_block=""
  if [[ "$emitted" != "true" ]]; then
    resolved_persisted=$(jq -c --argjson idx "$step_idx" \
      '.steps[$idx].resolved_inputs // {}' "$sf" 2>/dev/null || printf '{}')
    contract_block=$(context_compose_contract_block "$step" "$resolved_persisted")
    if [[ -n "$contract_block" ]]; then
      state_set_contract_emitted "$sf" "$step_idx" "true"
    fi
  fi
  if [[ -n "$contract_block" ]]; then
    body="${contract_block}"$'\n\n'"${rem}"
  else
    body="$rem"
  fi
  printf '%s' "$body"
}

# Tick 1: contract block emitted, flag flipped to true.
body1=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")
flag_after_1=$(state_get_contract_emitted "$SF" 0)

if [[ "$body1" == *"## Resolved Inputs"* && "$body1" == *"## Step Instruction"* && "$body1" == *"## Required Output Schema"* ]]; then
  assert_pass "T1 — Tick 1: contract block emitted (all three sections present)"
else
  assert_fail "T1 — Tick 1 missing sections; got: $body1"
fi
if [[ "$body1" == *"$REMINDER"* ]]; then
  assert_pass "T2 — Tick 1: reminder text present alongside contract block"
else
  assert_fail "T2 — reminder missing in tick 1"
fi
if [[ "$flag_after_1" == "true" ]]; then
  assert_pass "T3 — Tick 1: contract_emitted flipped to true"
else
  assert_fail "T3 — flag not flipped; got '$flag_after_1'"
fi

# Tick 2: contract block suppressed; reminder ONLY (FR-H2-5).
body2=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")
flag_after_2=$(state_get_contract_emitted "$SF" 0)

if [[ "$body2" == "$REMINDER" ]]; then
  assert_pass "T4 — FR-H2-5: Tick 2 emits ONLY the reminder (contract block suppressed)"
else
  assert_fail "T4 — Tick 2 contract block not suppressed; body: $body2"
fi
if [[ "$body2" != *"## Resolved Inputs"* && "$body2" != *"## Required Output Schema"* ]]; then
  assert_pass "T5 — FR-H2-5: contract sections absent on tick 2"
else
  assert_fail "T5 — sections leaked on tick 2"
fi
if [[ "$flag_after_2" == "true" ]]; then
  assert_pass "T6 — Tick 2: contract_emitted remains true (idempotent)"
else
  assert_fail "T6 — flag regressed; got '$flag_after_2'"
fi

# Tick 3 (idempotency): same as tick 2.
body3=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")
if [[ "$body3" == "$REMINDER" ]]; then
  assert_pass "T7 — Tick 3 still suppresses contract block (idempotent)"
else
  assert_fail "T7 — body3 wrong: $body3"
fi

# -----------------------------------------------------------------------------
# T8: NFR-H-2 mutation tripwire — disable state_set_contract_emitted (so the
# flag is never set) and assert tick 2 RE-EMITS. This proves the gating fires.
# -----------------------------------------------------------------------------
# Reset state
jq '.steps[0].contract_emitted = false' "$SF" > "$SF.tmp" && mv "$SF.tmp" "$SF"

# Mutate: stub state_set_contract_emitted to a no-op.
state_set_contract_emitted_real() { command true; }
# shellcheck disable=SC2034
_real_setter=$(declare -f state_set_contract_emitted)
state_set_contract_emitted() { return 0; }

body_m1=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")
body_m2=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")

if [[ "$body_m1" == *"## Resolved Inputs"* && "$body_m2" == *"## Resolved Inputs"* ]]; then
  assert_pass "T8 — NFR-H-2 tripwire: with setter mutated, BOTH ticks re-emit (regression to never-set would ship)"
else
  assert_fail "T8 — mutation didn't trigger re-emission; body_m1=$body_m1 body_m2=$body_m2"
fi

# Restore
unset -f state_set_contract_emitted
eval "$_real_setter"

# Final sanity: real setter still gates correctly.
jq '.steps[0].contract_emitted = false' "$SF" > "$SF.tmp" && mv "$SF.tmp" "$SF"
body_r1=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")
body_r2=$(compose_reminder_body "$SF" "$STEP" 0 "$REMINDER")
if [[ "$body_r1" == *"## Resolved Inputs"* && "$body_r2" == "$REMINDER" ]]; then
  assert_pass "T9 — control: real setter restored, gating works as designed"
else
  assert_fail "T9 — real setter regressed; body_r1=$body_r1 body_r2=$body_r2"
fi

rm -rf "$TMP"

echo
echo "==> contract-block-emit-once: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
