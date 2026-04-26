#!/usr/bin/env bash
# research-runner-axis-infra-zero-tolerance/run.sh — SC-AE-003 anchor.
#
# Validates User Story 3 (FR-AE-002 / FR-AE-005 — axis-aware eob polarity):
# A PRD declaring `blast_radius: infra` (rigor row: tolerance_pct=0) +
# `empirical_quality: [{metric: tokens, direction: equal_or_better}]` whose
# candidate produces +1 token on a single fixture MUST fail with
# `Overall: FAIL`. Zero-token-drift on every fixture → PASS.
#
# Pure-shell unit fixture per the test substrate hierarchy. Drives
# evaluate-direction.sh + renderer with synthetic NDJSON; verifies the
# per-axis verdict logic that the runner integrates.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
evaluator="$repo_root/plugin-wheel/scripts/harness/evaluate-direction.sh"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: infra blast + tokens equal_or_better + tolerance_pct=0 + +1 token on
# a single fixture → regression.
# Anchors: User Story 3 acceptance scenario 1, axis-aware eob polarity.
v=$(bash "$evaluator" --axis tokens --direction equal_or_better --tolerance-pct 0 --baseline 100 --candidate 101)
[[ $v == "regression" ]] || fail "expected regression for tokens+eob+tol=0, b=100, c=101 — got $v"
assertions=$((assertions + 1))

# A2: zero-token-drift → PASS.
# Anchors: User Story 3 acceptance scenario 2.
v=$(bash "$evaluator" --axis tokens --direction equal_or_better --tolerance-pct 0 --baseline 100 --candidate 100)
[[ $v == "pass" ]] || fail "expected pass for tokens+eob+tol=0, b=100, c=100 — got $v"
assertions=$((assertions + 1))

# A3: tokens DIRECTION=lower with zero-drift → PASS (acceptance scenario 3).
# Anchors: User Story 3 acceptance scenario 3 (eob and lower both accept zero-delta).
v=$(bash "$evaluator" --axis tokens --direction lower --tolerance-pct 0 --baseline 100 --candidate 100)
[[ $v == "pass" ]] || fail "expected pass for tokens+lower+tol=0, b=100, c=100 — got $v"
assertions=$((assertions + 1))

# A4: tokens DIRECTION=lower with +1 → regression (loud-failure).
v=$(bash "$evaluator" --axis tokens --direction lower --tolerance-pct 0 --baseline 100 --candidate 101)
[[ $v == "regression" ]] || fail "expected regression for tokens+lower+tol=0, b=100, c=101 — got $v"
assertions=$((assertions + 1))

# A5: synthesize per-fixture NDJSON for SC-AE-003 — drive renderer.
# Single fixture in a 20-fixture-corpus context (we only render one row;
# the runner-level integration handles the corpus loop).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ndjson="$tmp/results.ndjson"
slug="010-token-plus-one"
jq -nc \
  --arg slug "$slug" \
  '{fixture_slug:$slug, fixture_path:"/abs/x",
    baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:50,output:50,cached_creation:0,cached_read:0,total:100},time_seconds:5.0,cost_usd:null,model_id:null},
    candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:50,output:51,cached_creation:0,cached_read:0,total:101},time_seconds:5.0,cost_usd:null,model_id:null},
    delta_tokens:1, delta_time_seconds:0, delta_cost_usd:null,
    verdict:"regression (tokens)",
    per_axis_verdicts:{accuracy:"pass",tokens:"regression",time:"not-enforced",cost:"not-enforced"}}' >"$ndjson"

RESEARCH_REPORT_RUN_UUID=test-uuid \
RESEARCH_REPORT_PRD=/abs/prd.md \
RESEARCH_REPORT_GATE_MODE=per_axis_direction \
RESEARCH_REPORT_BLAST_RADIUS=infra \
RESEARCH_REPORT_RIGOR_ROW="min_fixtures=20, tolerance_pct=0" \
RESEARCH_REPORT_DECLARED_AXES="tokens (equal_or_better)" \
  bash "$renderer" "$tmp/report.md" <"$ndjson"

grep -qE 'Overall\*?\*?: FAIL' "$tmp/report.md" || fail "report missing 'Overall: FAIL'"
grep -qF 'tokens:regression' "$tmp/report.md" || fail "report missing 'tokens:regression'"
grep -qF 'Blast radius**: infra' "$tmp/report.md" || fail "report missing 'Blast radius: infra'"
grep -qF 'tolerance_pct=0' "$tmp/report.md" || fail "report missing tolerance_pct=0"
assertions=$((assertions + 4))

echo "PASS ($assertions assertions)"
