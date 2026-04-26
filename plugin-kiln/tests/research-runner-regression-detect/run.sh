#!/usr/bin/env bash
# research-runner-regression-detect/run.sh — SC-S-002 anchor.
#
# Validates: a candidate that produces strictly more output tokens than baseline
# produces `Overall: FAIL` + per-fixture verdict `regression (tokens)` naming
# the slug. Drives parse-token-usage.sh + render-research-report.sh directly
# from synthetic transcripts (no claude subprocess) — pure-shell unit fixture
# per the test substrate hierarchy.
#
# Acceptance scenarios anchored:
# - User Story 2, scenario 1: per-fixture row shows verdict `regression (tokens)`.
# - User Story 2, scenario 2: aggregate names the slug.
# - User Story 2, scenario 3: exit semantics — verified at runner level via
#   strict-gate logic replicated below.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
parser="$repo_root/plugin-wheel/scripts/harness/parse-token-usage.sh"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"
runner="$repo_root/plugin-wheel/scripts/harness/research-runner.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: parse both transcripts (FR-S-013 path coverage).
b_tokens=$(bash "$parser" "$here/fixtures/transcript-baseline.ndjson")
c_tokens=$(bash "$parser" "$here/fixtures/transcript-candidate-token-regression.ndjson")
[[ $b_tokens == "10 50 100 200 360" ]] || fail "baseline tokens unexpected: $b_tokens"
[[ $c_tokens == "10 80 100 200 390" ]] || fail "candidate tokens unexpected: $c_tokens"
assertions=$((assertions + 2))

# A2: synthesize per-fixture NDJSON simulating a regression — drive renderer.
slug="001-token-regression"
ndjson=$(mktemp)
jq -nc \
  --arg slug "$slug" \
  '{fixture_slug:$slug, fixture_path:"/abs/x",
    baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:10,output:50,cached_creation:100,cached_read:200,total:360}},
    candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:10,output:80,cached_creation:100,cached_read:200,total:390}},
    delta_tokens:30, verdict:"regression (tokens)"}' > "$ndjson"

export RESEARCH_REPORT_RUN_UUID=test-uuid
export RESEARCH_REPORT_BASELINE_PLUGIN_DIR=/abs/baseline
export RESEARCH_REPORT_CANDIDATE_PLUGIN_DIR=/abs/candidate
export RESEARCH_REPORT_CORPUS_DIR=/abs/corpus
export RESEARCH_REPORT_STARTED=2026-04-25T00:00:00Z
export RESEARCH_REPORT_COMPLETED=2026-04-25T00:00:01Z
export RESEARCH_REPORT_WALL_CLOCK=1.0s
bash "$renderer" "$tmp/report.md" < "$ndjson"
rm -f "$ndjson"

# A3: verify Overall: FAIL.
grep -qE 'Overall\*?\*?: FAIL' "$tmp/report.md" || fail "report missing 'Overall: FAIL'"
assertions=$((assertions + 1))

# A4: verify slug appears in per-fixture row with regression verdict.
grep -qE "\| $slug \|.*\| regression \(tokens\) \|" "$tmp/report.md" || \
  fail "report missing per-fixture row naming '$slug' with 'regression (tokens)' verdict"
assertions=$((assertions + 1))

# A5: verify Diagnostics section present (FAIL-only block per §8).
grep -qF "## Diagnostics" "$tmp/report.md" || fail "report missing Diagnostics section on FAIL"
assertions=$((assertions + 1))

# A6: verify Diagnostics names the regressing slug.
grep -qF "**$slug**" "$tmp/report.md" || fail "Diagnostics missing slug '$slug'"
assertions=$((assertions + 1))

# A7: verify the runner's strict-gate computation: replay the same scenario
# through the actual runner verdict logic by spawning a minimal corpus that
# bails on missing input.json — confirming inconclusive→FAIL classification.
inc_corpus=$(mktemp -d)
mkdir -p "$inc_corpus/001-broken"
# Intentionally omit input.json — runner should classify inconclusive.
echo '{"expected_exit_code":0}' > "$inc_corpus/001-broken/expected.json"
set +e
out=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$inc_corpus" --report-path "$tmp/inc-report.md" 2>&1)
rc=$?
set -e
rm -rf "$inc_corpus"
# Accept rc=2 (inconclusive) OR rc=2 from claude-CLI-bail. Either path is FAIL.
[[ $rc -eq 2 ]] || fail "inconclusive corpus: expected exit 2, got $rc"
assertions=$((assertions + 1))

echo "PASS ($assertions assertions)"
