#!/usr/bin/env bash
# T022 / SC-010 / FR-014 — classifier axis-inference mapping fixture.
# For each row in the FR-014 axis-inference table, assert the classifier's
# proposed_axes[] matches the expected axes.
# Substrate: tier-2 (run.sh-only).
#
# Invoke: bash plugin-kiln/tests/classifier-axis-inference-mapping/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/plugin-kiln/scripts/roadmap/classify-description.sh"

[[ -x "$CLASSIFIER" ]] || { echo "FAIL: classifier missing"; exit 2; }

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

# Helper: assert that a description produces a specific set of axis metrics.
assert_axes() {
  local desc="$1"; local expected_metrics="$2"
  local out
  out=$(bash "$CLASSIFIER" "$desc")
  local actual
  actual=$(printf '%s' "$out" | jq -r '.research_inference.proposed_axes // [] | [.[].metric] | sort | join(",")')
  if [ "$actual" = "$expected_metrics" ]; then
    PASS=$((PASS+1)); printf '  pass  "%s" → axes [%s]\n' "$desc" "$expected_metrics"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  "%s" → expected [%s], got [%s]\n' "$desc" "$expected_metrics" "$actual"
  fi
}

# FR-014 row 1: faster | slower | latency → time:lower
assert_axes "make this faster"           "time"
assert_axes "the api is slower than"     "time"
assert_axes "investigate the latency"    "time"

# FR-014 row 2: cheaper | tokens | cost | "more expensive" | expensive → cost + tokens
assert_axes "make claude cheaper"        "cost,tokens"
assert_axes "this is more expensive"     "cost,tokens"
assert_axes "kind of expensive run"      "cost,tokens"

# FR-014 row 3: smaller | concise | verbose → tokens
assert_axes "make output smaller"        "tokens"
assert_axes "more concise responses"     "tokens"
assert_axes "the output is too verbose"  "tokens"

# FR-014 row 4: accurate | wrong | regression → accuracy:equal_or_better
assert_axes "more accurate parsing"      "accuracy"
assert_axes "the answer is wrong"        "accuracy"
assert_axes "fix the regression"         "accuracy"

# FR-014 row 5: clearer | better-structured | more actionable → output_quality:equal_or_better
assert_axes "clearer error messages"          "output_quality"
assert_axes "make outputs better-structured"  "output_quality"
assert_axes "results should be more actionable" "output_quality"

# FR-014 row 6: signal-only — needs_research:true with empty proposed_axes
assert_axes "improve the dashboard"      ""
assert_axes "compare to the baseline"    ""
assert_axes "we should optimize"         ""

# Verify each inferred axis defaults priority: primary
out=$(bash "$CLASSIFIER" "make claude cheaper")
assert "every axis defaults priority: primary" \
  bash -c "echo '$out' | jq -e '.research_inference.proposed_axes | all(.priority == \"primary\")' >/dev/null"

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
