#!/usr/bin/env bash
# T025 — contract-block-shape fixture.
#
# specs/wheel-typed-schema-locality acceptance scenarios covered:
#   User Story 2 — Acceptance Scenarios 1, 2, 3 (shape of all three sections).
#
# FRs covered:
#   FR-H2-1 (## Resolved Inputs block, same content as dispatch's
#            context_build prepend)
#   FR-H2-2 (## Step Instruction post-{{VAR}}-substitution)
#   FR-H2-3 (## Required Output Schema fenced JSON code block)
#   FR-H2-6 (deterministic order: Resolved Inputs → Step Instruction →
#            Required Output Schema)
#   FR-H2-7 (no contract on advance-past-done — implicit, the composer
#            is only invoked from the working+output-not-yet-produced branch)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"

# shellcheck source=../../lib/preprocess.sh
source "${WHEEL_LIB_DIR}/preprocess.sh"
# shellcheck source=../../lib/context.sh
source "${WHEEL_LIB_DIR}/context.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Step declaring all three.
STEP=$(cat <<'EOF'
{
  "id": "shape-test",
  "inputs": {
    "ISSUE_FILE": "$.steps.s1.output.path",
    "AUTHOR": "$.steps.s1.output.author"
  },
  "instruction": "Process {{ISSUE_FILE}} by {{AUTHOR}}.",
  "output_schema": {
    "issue_file": "$.issue_file",
    "status": "$.status"
  }
}
EOF
)
RESOLVED='{"ISSUE_FILE":"/tmp/issue-1.md","AUTHOR":"alice"}'

OUT=$(context_compose_contract_block "$STEP" "$RESOLVED")

# T1: all three section headers present.
if [[ "$OUT" == *"## Resolved Inputs"* ]]; then
  assert_pass "T1 — FR-H2-1: ## Resolved Inputs heading present"
else
  assert_fail "T1 — heading missing; got: $OUT"
fi
if [[ "$OUT" == *"## Step Instruction"* ]]; then
  assert_pass "T2 — FR-H2-2: ## Step Instruction heading present"
else
  assert_fail "T2 — heading missing"
fi
if [[ "$OUT" == *"## Required Output Schema"* ]]; then
  assert_pass "T3 — FR-H2-3: ## Required Output Schema heading present"
else
  assert_fail "T3 — heading missing"
fi

# T4: deterministic order (FR-H2-6).
ri_pos=$(awk '/^## Resolved Inputs$/{print NR}' <<<"$OUT" | head -1)
si_pos=$(awk '/^## Step Instruction$/{print NR}' <<<"$OUT" | head -1)
ro_pos=$(awk '/^## Required Output Schema$/{print NR}' <<<"$OUT" | head -1)
if [[ -n "$ri_pos" && -n "$si_pos" && -n "$ro_pos" && "$ri_pos" -lt "$si_pos" && "$si_pos" -lt "$ro_pos" ]]; then
  assert_pass "T4 — FR-H2-6: section order Resolved Inputs → Step Instruction → Required Output Schema"
else
  assert_fail "T4 — section order wrong (ri=$ri_pos si=$si_pos ro=$ro_pos)"
fi

# T5: per-input bullet shape FR-H2-1: `- **<VAR>**: <value>`.
if [[ "$OUT" == *"- **ISSUE_FILE**: /tmp/issue-1.md"* ]]; then
  assert_pass "T5 — FR-H2-1: per-input bullet shape '- **<VAR>**: <value>'"
else
  assert_fail "T5 — bullet shape wrong; got: $OUT"
fi
if [[ "$OUT" == *"- **AUTHOR**: alice"* ]]; then
  assert_pass "T6 — FR-H2-1: second input bullet present"
else
  assert_fail "T6 — second bullet missing"
fi

# T7: instruction post-{{VAR}}-substitution (FR-H2-2).
if [[ "$OUT" == *"Process /tmp/issue-1.md by alice."* ]]; then
  assert_pass "T7 — FR-H2-2: {{VAR}} placeholders substituted"
else
  assert_fail "T7 — substitution didn't run; instruction text in output: $OUT"
fi
if [[ "$OUT" != *"{{ISSUE_FILE}}"* && "$OUT" != *"{{AUTHOR}}"* ]]; then
  assert_pass "T8 — FR-H2-2: no residual {{VAR}} placeholders"
else
  assert_fail "T8 — {{VAR}} placeholders not all substituted"
fi

# T9: schema rendered as fenced JSON code block (FR-H2-3).
if [[ "$OUT" == *'```json'* && "$OUT" == *'"issue_file"'* && "$OUT" == *'```'* ]]; then
  assert_pass "T9 — FR-H2-3: schema rendered as fenced JSON code block"
else
  assert_fail "T9 — schema rendering wrong"
fi

# T10: schema content is the .output_schema serialization (jq -c).
expected_schema=$(printf '%s' "$STEP" | jq -c '.output_schema')
if [[ "$OUT" == *"$expected_schema"* ]]; then
  assert_pass "T10 — FR-H2-3: schema body matches jq -c .output_schema verbatim"
else
  assert_fail "T10 — schema body mismatch; expected: $expected_schema"
fi

# T11: ## Resolved Inputs content matches what context_build prepends at
# dispatch (FR-H2-1 same-content invariant). Compare bullet block character
# by character.
expected_resolved_block=$(printf '%s' "$RESOLVED" | jq -r '
  "## Resolved Inputs\n" +
  ([to_entries[] | "- **" + .key + "**: " + (.value | tostring)] | join("\n"))
')
if [[ "$OUT" == *"$expected_resolved_block"* ]]; then
  assert_pass "T11 — FR-H2-1: Resolved Inputs block byte-matches dispatch composer"
else
  assert_fail "T11 — Resolved Inputs content mismatch:"$'\n'"--expected--"$'\n'"$expected_resolved_block"$'\n'"--actual--"$'\n'"$OUT"
fi

echo
echo "==> contract-block-shape: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
