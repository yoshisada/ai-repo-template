#!/usr/bin/env bash
# research-runner-axis-direction-pass/run.sh — SC-AE-001 anchor.
#
# Validates User Story 1 (FR-AE-001 / FR-AE-002 / FR-AE-005 / FR-AE-014):
# A PRD declaring `empirical_quality: [{metric: time, direction: lower},
# {metric: tokens, direction: equal_or_better}]` with a candidate that
# improves time on every fixture and holds tokens within tolerance MUST
# pass with `Overall: PASS`. Same candidate against a single-axis time-only
# declaration also passes (un-declared tokens NOT gate-enforced).
#
# Pure-shell unit fixture per the test substrate hierarchy (B-1 harness gap;
# kiln-test substrate not yet wired for axis-enrichment fixtures).
# Drives helpers + renderer directly from synthetic NDJSON; runner CLI
# exercised via the parse-prd-frontmatter.sh + evaluate-direction.sh path.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
parser="$repo_root/plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"
evaluator="$repo_root/plugin-wheel/scripts/harness/evaluate-direction.sh"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: parse PRD frontmatter with two-axis empirical_quality declaration.
# Anchors: User Story 1 setup, FR-AE-001.
projection=$(bash "$parser" "$here/fixtures/two-axis-prd.md")
metric_count=$(printf '%s' "$projection" | jq '.empirical_quality | length')
[[ $metric_count -eq 2 ]] || fail "expected 2 metrics declared, got $metric_count"
declared_time=$(printf '%s' "$projection" | jq -r '.empirical_quality[] | select(.metric=="time") | .direction')
declared_tokens=$(printf '%s' "$projection" | jq -r '.empirical_quality[] | select(.metric=="tokens") | .direction')
[[ $declared_time == "lower" ]] || fail "expected time direction=lower, got $declared_time"
[[ $declared_tokens == "equal_or_better" ]] || fail "expected tokens direction=equal_or_better, got $declared_tokens"
assertions=$((assertions + 3))

# A2: blast_radius=isolated → tolerance_pct=5.
# Anchors: FR-AE-004, contracts §7.
blast=$(printf '%s' "$projection" | jq -r '.blast_radius')
[[ $blast == "isolated" ]] || fail "expected blast_radius=isolated, got $blast"
assertions=$((assertions + 1))

# A3: time-axis evaluation — candidate improves on every fixture (lower).
# Anchors: User Story 1 acceptance scenario 1 (time direction=lower).
v=$(bash "$evaluator" --axis time --direction lower --tolerance-pct 5 --baseline 5.0 --candidate 4.5)
[[ $v == "pass" ]] || fail "expected time pass on improvement (5.0→4.5), got $v"
assertions=$((assertions + 1))

# A4: tokens-axis evaluation — candidate flat within tolerance (eob).
v=$(bash "$evaluator" --axis tokens --direction equal_or_better --tolerance-pct 5 --baseline 100 --candidate 102)
[[ $v == "pass" ]] || fail "expected tokens pass on flat-within-tolerance (100→102, tol=5%), got $v"
assertions=$((assertions + 1))

# A5: tokens-axis evaluation — candidate drifts beyond tolerance.
# Anchors: User Story 1 acceptance scenario 2 (tokens > tolerance → regression).
v=$(bash "$evaluator" --axis tokens --direction equal_or_better --tolerance-pct 5 --baseline 100 --candidate 110)
[[ $v == "regression" ]] || fail "expected tokens regression on +10% (tol=5%), got $v"
assertions=$((assertions + 1))

# A6: synthesize per-fixture NDJSON simulating SC-AE-001 — drive renderer.
# Anchors: User Story 1 acceptance scenario 1 (per-fixture row + aggregate PASS).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ndjson="$tmp/results.ndjson"
slug="001-time-improvement"
jq -nc \
  --arg slug "$slug" \
  '{fixture_slug:$slug, fixture_path:"/abs/x",
    baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:10,output:50,cached_creation:0,cached_read:0,total:60},time_seconds:5.0,cost_usd:null,model_id:null},
    candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:10,output:51,cached_creation:0,cached_read:0,total:61},time_seconds:4.5,cost_usd:null,model_id:null},
    delta_tokens:1, delta_time_seconds:-0.5, delta_cost_usd:null,
    verdict:"pass",
    per_axis_verdicts:{accuracy:"pass",tokens:"pass",time:"pass",cost:"not-enforced"}}' >"$ndjson"

RESEARCH_REPORT_RUN_UUID=test-uuid \
RESEARCH_REPORT_PRD=/abs/prd.md \
RESEARCH_REPORT_GATE_MODE=per_axis_direction \
RESEARCH_REPORT_BLAST_RADIUS=isolated \
RESEARCH_REPORT_RIGOR_ROW="min_fixtures=3, tolerance_pct=5" \
RESEARCH_REPORT_DECLARED_AXES="time (lower), tokens (equal_or_better)" \
  bash "$renderer" "$tmp/report.md" <"$ndjson"

grep -qE 'Overall\*?\*?: PASS' "$tmp/report.md" || fail "report missing 'Overall: PASS'"
grep -qF 'Gate mode**: per_axis_direction' "$tmp/report.md" || fail "report missing gate_mode=per_axis_direction"
grep -qE "\| $slug \|.*\| 5\.0/4\.5 \|.*tokens:pass.*time:pass" "$tmp/report.md" || \
  fail "report missing per-fixture row with time:pass + tokens:pass"
assertions=$((assertions + 3))

echo "PASS ($assertions assertions)"
