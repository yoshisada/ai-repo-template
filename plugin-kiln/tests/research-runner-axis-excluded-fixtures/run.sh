#!/usr/bin/env bash
# research-runner-axis-excluded-fixtures/run.sh — SC-AE-006 anchor.
#
# Validates User Story 5 (FR-AE-006, FR-AE-007):
# `excluded_fixtures: [{path, reason}]` causes the named fixture to be
# skipped (no scratch dirs created), recorded in the "Excluded" section,
# and counted AGAINST `min_fixtures` (excluded fixtures do NOT satisfy
# the floor).
#
# Pure-shell unit fixture per the test substrate hierarchy. Drives the
# runner CLI (PRE-subprocess paths only) + parse-prd-frontmatter.sh +
# renderer with synthetic NDJSON.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
runner="$repo_root/plugin-wheel/scripts/harness/research-runner.sh"
parser="$repo_root/plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: parse PRD with excluded_fixtures.
# Anchors: FR-AE-006 — excluded_fixtures shape.
projection=$(bash "$parser" "$here/fixtures/excluded-prd.md")
ex_count=$(printf '%s' "$projection" | jq '.excluded_fixtures | length')
[[ $ex_count -eq 1 ]] || fail "expected 1 excluded fixture, got $ex_count"
ex_path=$(printf '%s' "$projection" | jq -r '.excluded_fixtures[0].path')
ex_reason=$(printf '%s' "$projection" | jq -r '.excluded_fixtures[0].reason')
[[ $ex_path == "002-flaky" ]] || fail "expected excluded path=002-flaky, got $ex_path"
[[ -n $ex_reason ]] || fail "expected non-empty exclude reason"
assertions=$((assertions + 3))

# A2: build a 4-fixture corpus with one fixture matching the excluded path.
# Anchors: User Story 5 acceptance scenario 1 (4 declared - 1 excluded = 3 active).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/corpus"
for slug in 001-active 002-flaky 003-active 004-active; do
  dir="$tmp/corpus/$slug"
  mkdir -p "$dir"
  printf '{"type":"user","message":{"role":"user","content":"/help"}}\n' >"$dir/input.json"
  printf '{"expected_exit_code":0}\n' >"$dir/expected.json"
done
assertions=$((assertions + 1))

# A3: invoke runner — isolated blast (min_fixtures=3) + 1 excluded → exactly 3 active fixtures.
# Runner may fail later for missing claude CLI but excluded_fixtures parse + min_fixtures check
# happen PRE-subprocess. We check that no min_fixtures-not-met diagnostic fires.
set +e
out=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --prd "$here/fixtures/excluded-prd.md" 2>&1)
rc=$?
set -e
echo "$out" | grep -qF "min-fixtures-not-met" && \
  fail "runner incorrectly reported min-fixtures-not-met for 3 active (4-1 excluded) vs floor 3 (output: $out)"
assertions=$((assertions + 1))

# A4: invoke runner with 4-fixture corpus + 2 excluded fixtures + min_fixtures=3 → fail-fast.
# Anchors: User Story 5 acceptance scenario 2.
set +e
out2=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --prd "$here/fixtures/excluded-2-prd.md" 2>&1)
rc2=$?
set -e
[[ $rc2 -eq 2 ]] || fail "expected exit 2 for 2-excluded < min_fixtures=3, got $rc2"
echo "$out2" | grep -qF "min-fixtures-not-met: 2 < 3" || \
  fail "diagnostic missing 'min-fixtures-not-met: 2 < 3' (output: $out2)"
echo "$out2" | grep -qF "2 fixtures excluded" || \
  fail "diagnostic missing '2 fixtures excluded' citation (output: $out2)"
assertions=$((assertions + 3))

# A5: excluded path that doesn't exist in corpus → bail-out.
# Anchors: §Edge Case "excluded_fixtures references a path that doesn't exist".
set +e
out3=$(bash "$runner" --baseline "$repo_root/plugin-kiln" --candidate "$repo_root/plugin-kiln" \
                     --corpus "$tmp/corpus" --prd "$here/fixtures/excluded-bad-path-prd.md" 2>&1)
rc3=$?
set -e
[[ $rc3 -eq 2 ]] || fail "expected exit 2 for excluded-not-in-corpus, got $rc3"
echo "$out3" | grep -qF "excluded_fixtures path not found in corpus" || \
  fail "diagnostic missing 'excluded_fixtures path not found in corpus' (output: $out3)"
assertions=$((assertions + 2))

# A6: render Excluded Fixtures section.
# Anchors: User Story 5 acceptance scenario 1 ("recorded in the report's 'Excluded' section").
ndjson="$tmp/results.ndjson"
jq -nc \
  '{fixture_slug:"001-active", fixture_path:"/abs/x",
    baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:10,output:10,cached_creation:0,cached_read:0,total:20},time_seconds:5.0,cost_usd:null,model_id:null},
    candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:10,output:10,cached_creation:0,cached_read:0,total:20},time_seconds:5.0,cost_usd:null,model_id:null},
    delta_tokens:0, delta_time_seconds:0, delta_cost_usd:null,
    verdict:"pass",
    per_axis_verdicts:{accuracy:"pass",tokens:"pass",time:"pass",cost:"not-enforced"}}' >"$ndjson"

ex_tsv="$tmp/excluded.tsv"
printf '002-flaky\tintermittent stream-json shape drift\n' >"$ex_tsv"

RESEARCH_REPORT_RUN_UUID=test-uuid \
RESEARCH_REPORT_GATE_MODE=per_axis_direction \
RESEARCH_REPORT_BLAST_RADIUS=isolated \
RESEARCH_REPORT_RIGOR_ROW="min_fixtures=3, tolerance_pct=5" \
RESEARCH_REPORT_DECLARED_AXES="tokens (equal_or_better)" \
RESEARCH_REPORT_EXCLUDED_COUNT=1 \
RESEARCH_REPORT_EXCLUDED_TSV="$ex_tsv" \
  bash "$renderer" "$tmp/report.md" <"$ndjson"

grep -qF "## Excluded Fixtures" "$tmp/report.md" || fail "report missing 'Excluded Fixtures' section"
grep -qF "002-flaky" "$tmp/report.md" || fail "report missing '002-flaky' in excluded section"
grep -qF "intermittent stream-json shape drift" "$tmp/report.md" || \
  fail "report missing exclusion reason"
grep -qF "Excluded fixtures**: 1" "$tmp/report.md" || fail "aggregate missing 'Excluded fixtures: 1'"
assertions=$((assertions + 4))

echo "PASS ($assertions assertions)"
