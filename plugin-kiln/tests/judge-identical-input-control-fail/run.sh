#!/usr/bin/env bash
# T017 — SC-008 / FR-016.
# Asserts: when the judge returns A_better on the identical-input control
# fixture, the orchestrator halts with `Bail out! judge-drift-detected:
# blinded_verdict=A_better` and writes .kiln/research/<prd-slug>/judge-drift-report.md
# capturing the control inputs, verbatim judge prompt, and verdict envelope.
# Substrate: tier-2 (run.sh-only). Judge mocked via KILN_TEST_MOCK_JUDGE_DIR.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EVALUATOR="$REPO_ROOT/plugin-wheel/scripts/harness/evaluate-output-quality.sh"

[[ -x "$EVALUATOR" ]] || { echo "FAIL: evaluator not at $EVALUATOR"; exit 2; }

TMP=$(mktemp -d)
PRD_SLUG="t017-drift-detected"
ACTUAL_DIR="$REPO_ROOT/.kiln/research/$PRD_SLUG"
trap 'rm -rf "$TMP" "$ACTUAL_DIR"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

# Build a 3-fixture corpus. We need to determine which fixture the
# orchestrator picks as the control via sha256(<slug>:control) mod 3.
CONTROL_IDX=$(python3 -c '
import hashlib
print(int(hashlib.sha256(b"'"$PRD_SLUG"':control").hexdigest(), 16) % 3)
')
FIXTURE_IDS=(001-alpha 002-beta 003-gamma)
CONTROL_FID=${FIXTURE_IDS[$CONTROL_IDX]}

BASELINE="$TMP/baseline"; CANDIDATE="$TMP/candidate"; MOCK="$TMP/mocks"
mkdir -p "$BASELINE" "$CANDIDATE" "$MOCK"

for fid in "${FIXTURE_IDS[@]}"; do
  printf 'baseline-%s\n' "$fid" > "$BASELINE/$fid.txt"
  printf 'candidate-%s\n' "$fid" > "$CANDIDATE/$fid.txt"
done

cat > "$TMP/fixtures.json" <<EOF
{"fixtures": [
  {"id": "${FIXTURE_IDS[0]}"},
  {"id": "${FIXTURE_IDS[1]}"},
  {"id": "${FIXTURE_IDS[2]}"}
]}
EOF

cat > "$TMP/judge-config.yaml" <<'EOF'
pinned_model: claude-opus-4-7
EOF

# Mock judge envelopes — control returns A_better (drift!), others equal.
for fid in "${FIXTURE_IDS[@]}"; do
  local_verdict="equal"
  [[ "$fid" == "$CONTROL_FID" ]] && local_verdict="A_better"
  cat > "$MOCK/$fid.json" <<JSON
{
  "axis_id": "output_quality",
  "blinded_verdict": "$local_verdict",
  "fixture_id": "$fid",
  "model_used": "claude-opus-4-7",
  "rationale": "Mock rationale for $fid"
}
JSON
done

# Run evaluator — expect non-zero exit + drift report.
KILN_TEST_MOCK_JUDGE_DIR="$MOCK" \
  bash "$EVALUATOR" \
    --prd-slug "$PRD_SLUG" \
    --rubric-verbatim "Be clear and concrete." \
    --baseline-outputs "$BASELINE" \
    --candidate-outputs "$CANDIDATE" \
    --fixture-list "$TMP/fixtures.json" \
    --judge-config "$TMP/judge-config.yaml" \
    > "$TMP/stdout" 2> "$TMP/stderr"
EVAL_RC=$?

case_exit_2() { [[ "$EVAL_RC" == "2" ]]; }
assert_pass "Drift halt → exit 2" case_exit_2

case_bail_message() {
  grep -q -F "Bail out! judge-drift-detected: blinded_verdict=A_better" "$TMP/stderr"
}
assert_pass "Stderr contains 'Bail out! judge-drift-detected: blinded_verdict=A_better'" case_bail_message

case_drift_report_written() { [[ -f "$ACTUAL_DIR/judge-drift-report.md" ]]; }
assert_pass "judge-drift-report.md written" case_drift_report_written

case_drift_report_contents() {
  local r="$ACTUAL_DIR/judge-drift-report.md"
  grep -q -F "$CONTROL_FID" "$r" \
    && grep -q -F "blinded_verdict" "$r" \
    && grep -q -F "Rubric verbatim" "$r"
}
assert_pass "Drift report includes fixture id, verdict, rubric" case_drift_report_contents

# Crucially, the control envelope is NOT written when drift halts (per §1
# "Drift halt before write" final stanza).
case_no_control_envelope() {
  [[ ! -f "$ACTUAL_DIR/judge-verdicts/fixture-$CONTROL_FID.json" ]]
}
assert_pass "Control envelope NOT written on drift halt" case_no_control_envelope

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
