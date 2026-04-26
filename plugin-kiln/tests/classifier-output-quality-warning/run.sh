#!/usr/bin/env bash
# T023 / SC-011 / FR-016 — classifier output_quality warning + lint fixture.
# Asserts:
#   1. classifier output for "clearer" rationale contains the verbatim
#      FR-016 warning string.
#   2. lint script returns 0 against that output.
#   3. lint script returns 2 when the rationale is mutated to drop the warning.
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/classifier-output-quality-warning/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/plugin-kiln/scripts/roadmap/classify-description.sh"
LINT="$REPO_ROOT/plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh"

[[ -x "$CLASSIFIER" ]] || { echo "FAIL: classifier missing"; exit 2; }
[[ -x "$LINT" ]]       || { echo "FAIL: lint missing"; exit 2; }

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

WARNING='(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)'

# 1. classifier emits research_inference for "clearer" with output_quality.
OUT=$(bash "$CLASSIFIER" "make error messages clearer")

assert "classifier emits output_quality axis" \
  bash -c "echo '$OUT' | jq -e '.research_inference.proposed_axes | any(.metric == \"output_quality\")' >/dev/null"

assert "rationale contains FR-016 verbatim warning" \
  bash -c "echo '$OUT' | jq -r '.research_inference.rationale' | grep -qF -- '$WARNING'"

# 2. lint script passes against the classifier output.
assert "lint script exit 0 on valid classifier output" \
  bash -c "bash '$LINT' '$OUT' >/dev/null 2>&1"

# 3. Mutate rationale to drop the warning.
MUTATED=$(echo "$OUT" | jq -c '.research_inference.rationale = "matched signal word: clearer"')

assert "lint script exit 2 on missing warning (mutated input)" \
  bash -c "
    if bash '$LINT' '$MUTATED' >/dev/null 2>&1; then
      false
    else
      [ \$? -eq 2 ]
    fi
  "

# 4. Lint passes when output_quality is absent (nothing to lint).
NON_OQ=$(bash "$CLASSIFIER" "make this faster")
assert "lint exit 0 when no output_quality axis" \
  bash -c "bash '$LINT' '$NON_OQ' >/dev/null 2>&1"

# 5. Lint passes when no research_inference at all.
PLAIN='{"surface":"roadmap","kind":"feature","confidence":"high","alternatives":[]}'
assert "lint exit 0 when no research_inference" \
  bash -c "bash '$LINT' '$PLAIN' >/dev/null 2>&1"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
