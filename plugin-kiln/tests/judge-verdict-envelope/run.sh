#!/usr/bin/env bash
# T014 — SC-005 / contracts §1.
# Asserts: invoking evaluate-output-quality.sh with mocked judge envelopes
# produces canonical fixture-<id>.json files matching contracts §1 shape
# (8 fields: axis_id, blinded_verdict, blinded_position_mapping,
# deanonymized_verdict, fixture_id, is_control, model_used, rationale,
# rubric_verbatim_hash) — sorted-keys, jq -c -S byte-stable.
# Mock injection: KILN_TEST_MOCK_JUDGE_DIR points at pre-baked envelopes.
# Substrate: tier-2 (run.sh-only).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EVALUATOR="$REPO_ROOT/plugin-wheel/scripts/harness/evaluate-output-quality.sh"

[[ -x "$EVALUATOR" ]] || { echo "FAIL: evaluator not at $EVALUATOR"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

# Set up: 3 fixtures, baseline + candidate output dirs, mock judge dir.
PRD_SLUG="t014-envelope-shape"
FIXTURE_LIST="$TMP/fixtures.json"
BASELINE_DIR="$TMP/baseline"
CANDIDATE_DIR="$TMP/candidate"
MOCK_DIR="$TMP/mock-judges"
JUDGE_CFG="$TMP/judge-config.yaml"
mkdir -p "$BASELINE_DIR" "$CANDIDATE_DIR" "$MOCK_DIR"
# Redirect the evaluator's verdict writes into TMP (override .kiln/research/<slug>).
RESEARCH_DIR="$TMP/research/$PRD_SLUG"

cat > "$JUDGE_CFG" <<'EOF'
pinned_model: claude-opus-4-7
pinned_model_fallbacks:
  - claude-sonnet-4-6
EOF

cat > "$FIXTURE_LIST" <<'EOF'
{"fixtures": [
  {"id": "001-first", "path": "fixture-001-first.md"},
  {"id": "002-second", "path": "fixture-002-second.md"},
  {"id": "003-third", "path": "fixture-003-third.md"}
]}
EOF

for fid in 001-first 002-second 003-third; do
  printf 'baseline output for %s\n' "$fid" > "$BASELINE_DIR/$fid.txt"
  printf 'candidate output for %s\n' "$fid" > "$CANDIDATE_DIR/$fid.txt"
  cat > "$MOCK_DIR/$fid.json" <<JSON
{
  "axis_id": "output_quality",
  "blinded_verdict": "equal",
  "fixture_id": "$fid",
  "model_used": "claude-opus-4-7",
  "rationale": "Test rationale for $fid"
}
JSON
done

# Use a fake REPO_ROOT for verdict writes by symlinking .kiln/research/ override.
# evaluate-output-quality.sh derives REPO_ROOT relative to its own path; we
# instead override via a custom HOME-style trick: just check the canonical
# path under the real repo and clean up after.
ACTUAL_VERDICT_DIR="$REPO_ROOT/.kiln/research/$PRD_SLUG"
mkdir -p "$ACTUAL_VERDICT_DIR"
trap 'rm -rf "$TMP" "$ACTUAL_VERDICT_DIR"' EXIT

# Run evaluator with mocks.
KILN_TEST_MOCK_JUDGE_DIR="$MOCK_DIR" \
  bash "$EVALUATOR" \
    --prd-slug "$PRD_SLUG" \
    --rubric-verbatim "Be clear and concrete." \
    --baseline-outputs "$BASELINE_DIR" \
    --candidate-outputs "$CANDIDATE_DIR" \
    --fixture-list "$FIXTURE_LIST" \
    --judge-config "$JUDGE_CFG" \
    > "$TMP/stdout" 2> "$TMP/stderr"
EVAL_RC=$?

case_eval_rc_zero() { [[ "$EVAL_RC" == "0" ]]; }
assert_pass "Evaluator exits 0 on clean run" case_eval_rc_zero

case_stdout_pass() { grep -qx 'pass' "$TMP/stdout"; }
assert_pass "Stdout emits 'pass' for all-equal verdicts" case_stdout_pass

case_envelope_files_exist() {
  for fid in 001-first 002-second 003-third; do
    [[ -f "$ACTUAL_VERDICT_DIR/judge-verdicts/fixture-$fid.json" ]] || return 1
  done
}
assert_pass "Per-fixture envelope files written" case_envelope_files_exist

case_envelope_shape() {
  for fid in 001-first 002-second 003-third; do
    local f="$ACTUAL_VERDICT_DIR/judge-verdicts/fixture-$fid.json"
    # All 9 required fields present (incl. is_control + rubric_verbatim_hash).
    jq -e '
      (has("axis_id") and has("blinded_verdict") and has("blinded_position_mapping")
       and has("deanonymized_verdict") and has("fixture_id") and has("is_control")
       and has("model_used") and has("rationale") and has("rubric_verbatim_hash"))
      and (.axis_id == "output_quality")
      and (.fixture_id == "'"$fid"'")
      and (.rubric_verbatim_hash | test("^[0-9a-f]{64}$"))
      and (.blinded_position_mapping | has("A") and has("B"))
    ' "$f" >/dev/null || return 1
  done
}
assert_pass "Envelope contains all 9 fields with correct types" case_envelope_shape

case_byte_stable_jq_cS() {
  # Re-canonicalise via jq -c -S and assert byte-equal.
  for fid in 001-first 002-second 003-third; do
    local f="$ACTUAL_VERDICT_DIR/judge-verdicts/fixture-$fid.json"
    diff <(cat "$f") <(jq -c -S '.' "$f") >/dev/null || return 1
  done
}
assert_pass "Envelopes are jq -c -S canonical (sorted, no trailing ws)" case_byte_stable_jq_cS

case_position_mapping_written() {
  [[ -f "$ACTUAL_VERDICT_DIR/position-mapping.json" ]] || return 1
  jq -e '
    has("control_fixture_id") and has("fixture_assignments")
    and has("prd_slug") and (.schema_version == 1) and has("seed_algorithm")
  ' "$ACTUAL_VERDICT_DIR/position-mapping.json" >/dev/null
}
assert_pass "position-mapping.json written with §2 shape" case_position_mapping_written

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
