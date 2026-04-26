#!/usr/bin/env bash
# T021 — FR-014 / contracts §5.
# Asserts judge-config.yaml resolution behavior in evaluate-output-quality.sh:
#   1. Override at .kiln/research/judge-config.yaml wins over example.
#   2. Falls back to plugin-kiln/lib/judge-config.yaml.example when override absent.
#   3. Bails with `Bail out! judge-config-missing` when both absent (caller resolves).
#   4. Bails with `Bail out! judge-config-malformed` when override unparseable.
# The evaluator does NOT do the path-resolution itself (caller passes the
# already-resolved --judge-config path per §4 contract). So this test
# exercises BOTH (a) the malformed-detection inside the evaluator and (b) the
# resolution logic the SKILL.md prose documents (asserted structurally).
# Substrate: tier-2 (run.sh-only).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EVALUATOR="$REPO_ROOT/plugin-wheel/scripts/harness/evaluate-output-quality.sh"
SKILL="$REPO_ROOT/plugin-kiln/skills/plan/SKILL.md"
EXAMPLE="$REPO_ROOT/plugin-kiln/lib/judge-config.yaml.example"

TMP=$(mktemp -d)
PRD_SLUG="t021-judge-config"
ACTUAL_DIR="$REPO_ROOT/.kiln/research/$PRD_SLUG"
trap 'rm -rf "$TMP" "$ACTUAL_DIR"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

# Common harness for invoking the evaluator with a single-fixture corpus.
mkdir -p "$TMP/baseline" "$TMP/candidate" "$TMP/mocks"
printf 'baseline\n' > "$TMP/baseline/001-only.txt"
printf 'candidate\n' > "$TMP/candidate/001-only.txt"
cat > "$TMP/mocks/001-only.json" <<'JSON'
{"axis_id":"output_quality","blinded_verdict":"equal","fixture_id":"001-only","model_used":"claude-opus-4-7","rationale":"r"}
JSON
cat > "$TMP/fixtures.json" <<'EOF'
{"fixtures":[{"id":"001-only"}]}
EOF

run_eval_with_config() {
  local cfg_path="$1"
  KILN_TEST_MOCK_JUDGE_DIR="$TMP/mocks" \
    bash "$EVALUATOR" \
      --prd-slug "$PRD_SLUG" \
      --rubric-verbatim "Be clear." \
      --baseline-outputs "$TMP/baseline" \
      --candidate-outputs "$TMP/candidate" \
      --fixture-list "$TMP/fixtures.json" \
      --judge-config "$cfg_path" \
      > "$TMP/stdout" 2> "$TMP/stderr"
}

# Case 1: example fallback (committed default at plugin-kiln/lib/) is parseable + works.
case_example_works() {
  [[ -f "$EXAMPLE" ]] || return 1
  rm -rf "$ACTUAL_DIR"
  run_eval_with_config "$EXAMPLE"
  [[ "$?" == "0" ]]
}
assert_pass "judge-config.yaml.example parses + evaluator runs to pass" case_example_works

# Case 2: malformed override → bail.
case_malformed_override() {
  local bad="$TMP/bad.yaml"
  cat > "$bad" <<'EOF'
# missing required pinned_model
some_other_field: foo
EOF
  rm -rf "$ACTUAL_DIR"
  run_eval_with_config "$bad"
  local rc=$?
  [[ "$rc" == "2" ]] && grep -q -F "judge-config-malformed" "$TMP/stderr"
}
assert_pass "Malformed config (missing pinned_model) → bail judge-config-malformed" case_malformed_override

# Case 3: empty pinned_model → bail.
case_empty_pinned() {
  local bad="$TMP/empty-pinned.yaml"
  cat > "$bad" <<'EOF'
pinned_model:
EOF
  rm -rf "$ACTUAL_DIR"
  run_eval_with_config "$bad"
  local rc=$?
  [[ "$rc" == "2" ]] && grep -q -F "judge-config-malformed" "$TMP/stderr"
}
assert_pass "Empty pinned_model → bail judge-config-malformed" case_empty_pinned

# Case 4: missing config path → bail.
case_missing_path() {
  rm -rf "$ACTUAL_DIR"
  run_eval_with_config "$TMP/does-not-exist.yaml"
  [[ "$?" == "2" ]]
}
assert_pass "Missing config path → exit 2" case_missing_path

# Case 5: SKILL.md documents the two-path resolution order (FR-014).
case_skill_documents_resolution() {
  grep -q -F '.kiln/research/judge-config.yaml' "$SKILL" \
    && grep -q -F 'plugin-kiln/lib/judge-config.yaml.example' "$SKILL" \
    && grep -q -F 'judge-config-missing' "$SKILL"
}
assert_pass "SKILL.md documents two-path resolution + judge-config-missing bail" case_skill_documents_resolution

# Case 6: example schema has both required keys.
case_example_schema_complete() {
  grep -q -E '^pinned_model:[[:space:]]*claude-' "$EXAMPLE" \
    && grep -q -F 'pinned_model_fallbacks' "$EXAMPLE"
}
assert_pass "Example config has pinned_model + pinned_model_fallbacks" case_example_schema_complete

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
