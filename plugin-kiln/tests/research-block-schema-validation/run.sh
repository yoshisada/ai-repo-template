#!/usr/bin/env bash
# T021 / SC-009 / FR-001 / FR-003 / contracts §2 — schema validator fixture.
# Asserts validate-research-block.sh enforces every documented rule:
#   1. Clean item with all six fields → ok=true.
#   2. metric: foo → ok=false with 'unknown metric: foo'.
#   3. Absolute fixture_corpus_path → ok=false with bail message.
#   4. Unknown research-block key → ok=true + warning.
#   5. metric: output_quality without rubric → ok=false.
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/research-block-schema-validation/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/plugin-kiln/scripts/research/validate-research-block.sh"

[[ -x "$HELPER" ]] || { echo "FAIL: validator missing"; exit 2; }

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

# 1. Clean item with all six fields.
out=$(bash "$HELPER" '{
  "needs_research": true,
  "empirical_quality": [{"metric":"tokens","direction":"lower","priority":"primary"}],
  "fixture_corpus": "declared",
  "fixture_corpus_path": "fixtures/corpus/",
  "promote_synthesized": false,
  "excluded_fixtures": [{"path":"002-flaky","reason":"intermittent timeout"}]
}')
assert "clean six-field item → ok=true" \
  bash -c "echo '$out' | jq -e '.ok == true' >/dev/null"

# 2. Unknown metric.
out=$(bash "$HELPER" '{"empirical_quality":[{"metric":"foo","direction":"lower"}]}')
assert "unknown metric → ok=false" \
  bash -c "echo '$out' | jq -e '.ok == false' >/dev/null"
assert "unknown metric → error names 'foo'" \
  bash -c "echo '$out' | jq -e '.errors[] | contains(\"unknown metric: foo\")' >/dev/null"

# 3. Absolute fixture_corpus_path.
out=$(bash "$HELPER" '{"fixture_corpus":"declared","fixture_corpus_path":"/abs/path"}')
assert "absolute fixture_corpus_path → ok=false" \
  bash -c "echo '$out' | jq -e '.ok == false' >/dev/null"
assert "absolute fixture_corpus_path → 'fixture-corpus-path-must-be-relative' error" \
  bash -c "echo '$out' | jq -e '.errors[] | contains(\"fixture-corpus-path-must-be-relative\")' >/dev/null"

# 4. Unknown research-block-shaped key (warn-but-pass).
out=$(bash "$HELPER" '{"empirical_quality":[],"research_extra":"foo"}')
assert "unknown research-block key → ok=true" \
  bash -c "echo '$out' | jq -e '.ok == true' >/dev/null"
assert "unknown research-block key → warning emitted" \
  bash -c "echo '$out' | jq -e '.warnings[] | contains(\"unknown research-block field\")' >/dev/null"

# 5. output_quality without rubric.
out=$(bash "$HELPER" '{"empirical_quality":[{"metric":"output_quality","direction":"equal_or_better"}]}')
assert "output_quality without rubric → ok=false" \
  bash -c "echo '$out' | jq -e '.ok == false' >/dev/null"
assert "output_quality without rubric → error 'output_quality-axis-missing-rubric'" \
  bash -c "echo '$out' | jq -e '.errors[] | contains(\"output_quality-axis-missing-rubric\")' >/dev/null"

# 6. needs_research:true without fixture_corpus → warning (rule 10).
out=$(bash "$HELPER" '{"needs_research":true}')
assert "needs_research:true without fixture_corpus → ok=true with warning" \
  bash -c "echo '$out' | jq -e '.ok == true and (.warnings[] | contains(\"variant pipeline will bail at corpus-load\"))' >/dev/null"

# 7. fixture_corpus: declared without fixture_corpus_path → error.
out=$(bash "$HELPER" '{"fixture_corpus":"declared"}')
assert "declared without path → ok=false" \
  bash -c "echo '$out' | jq -e '.ok == false' >/dev/null"
assert "declared without path → 'fixture-corpus-path-required' error" \
  bash -c "echo '$out' | jq -e '.errors[] | contains(\"fixture-corpus-path-required\")' >/dev/null"

# 8. Duplicate metric in empirical_quality.
out=$(bash "$HELPER" '{"empirical_quality":[{"metric":"tokens","direction":"lower"},{"metric":"tokens","direction":"higher"}]}')
assert "duplicate metric → ok=false with 'duplicate metric: tokens'" \
  bash -c "echo '$out' | jq -e '.ok == false and (.errors[] | contains(\"duplicate metric: tokens\"))' >/dev/null"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
