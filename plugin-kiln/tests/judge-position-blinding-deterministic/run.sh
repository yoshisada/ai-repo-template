#!/usr/bin/env bash
# T018 — SC-009 / FR-015 / NFR-008 / contracts §2.
# Asserts: position-mapping.json is byte-identical across re-runs of the same
# (prd_slug, fixture_id_list). Validates the seed algorithm
# `sha256(prd_slug + ':' + fixture_id) mod 2` for a known triplet hand-verified
# below.
# Substrate: tier-2 (run.sh-only). Judge mocked.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EVALUATOR="$REPO_ROOT/plugin-wheel/scripts/harness/evaluate-output-quality.sh"

[[ -x "$EVALUATOR" ]] || { echo "FAIL: evaluator not at $EVALUATOR"; exit 2; }

TMP=$(mktemp -d)
PRD_SLUG="t018-pos-blinding"
ACTUAL_DIR="$REPO_ROOT/.kiln/research/$PRD_SLUG"
trap 'rm -rf "$TMP" "$ACTUAL_DIR"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

FIXTURE_IDS=(001-alpha 002-beta 003-gamma 004-delta)
BASELINE="$TMP/baseline"; CANDIDATE="$TMP/candidate"; MOCK="$TMP/mocks"
mkdir -p "$BASELINE" "$CANDIDATE" "$MOCK"

for fid in "${FIXTURE_IDS[@]}"; do
  printf 'baseline-%s\n' "$fid" > "$BASELINE/$fid.txt"
  printf 'candidate-%s\n' "$fid" > "$CANDIDATE/$fid.txt"
  cat > "$MOCK/$fid.json" <<JSON
{"axis_id":"output_quality","blinded_verdict":"equal","fixture_id":"$fid","model_used":"claude-opus-4-7","rationale":"r"}
JSON
done

cat > "$TMP/fixtures.json" <<EOF
{"fixtures": [
  {"id":"001-alpha"},{"id":"002-beta"},{"id":"003-gamma"},{"id":"004-delta"}
]}
EOF

cat > "$TMP/judge-config.yaml" <<'EOF'
pinned_model: claude-opus-4-7
EOF

run_eval() {
  KILN_TEST_MOCK_JUDGE_DIR="$MOCK" \
    bash "$EVALUATOR" \
      --prd-slug "$PRD_SLUG" \
      --rubric-verbatim "Be clear." \
      --baseline-outputs "$BASELINE" \
      --candidate-outputs "$CANDIDATE" \
      --fixture-list "$TMP/fixtures.json" \
      --judge-config "$TMP/judge-config.yaml" \
      > /dev/null 2>"$TMP/stderr_run"
}

# First run.
run_eval
cp "$ACTUAL_DIR/position-mapping.json" "$TMP/mapping1.json"

# Second run (overwrites).
run_eval
cp "$ACTUAL_DIR/position-mapping.json" "$TMP/mapping2.json"

case_byte_identical() {
  diff "$TMP/mapping1.json" "$TMP/mapping2.json" >/dev/null
}
assert_pass "Two runs produce byte-identical position-mapping.json" case_byte_identical

case_seed_algorithm_field() {
  jq -e '.seed_algorithm == "sha256(prd_slug + '\'':'\'' + fixture_id) mod 2"' "$TMP/mapping1.json" >/dev/null
}
assert_pass "seed_algorithm field documents the canonical algorithm" case_seed_algorithm_field

# Hand-verify ONE fixture's assignment against the documented algorithm.
case_hand_verified_assignment() {
  local fid="002-beta"
  local bit
  bit=$(python3 -c '
import hashlib, sys
print(int(hashlib.sha256(("t018-pos-blinding:" + sys.argv[1]).encode()).hexdigest(), 16) % 2)
' "$fid")
  local expected_a expected_b
  if [[ "$bit" == "0" ]]; then expected_a="baseline"; expected_b="candidate"
  else expected_a="candidate"; expected_b="baseline"; fi
  jq -e --arg fid "$fid" --arg a "$expected_a" --arg b "$expected_b" \
    '.fixture_assignments[$fid].A == $a and .fixture_assignments[$fid].B == $b' \
    "$TMP/mapping1.json" >/dev/null
}
assert_pass "Hand-verified assignment for 002-beta matches sha256-mod-2" case_hand_verified_assignment

# Control fixture has both positions = "baseline" per §2.
case_control_both_baseline() {
  local cid
  cid=$(jq -r .control_fixture_id "$TMP/mapping1.json")
  jq -e --arg fid "$cid" '.fixture_assignments[$fid].A == "baseline" and .fixture_assignments[$fid].B == "baseline"' "$TMP/mapping1.json" >/dev/null
}
assert_pass "Control fixture has A=baseline AND B=baseline (§2 invariant)" case_control_both_baseline

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
