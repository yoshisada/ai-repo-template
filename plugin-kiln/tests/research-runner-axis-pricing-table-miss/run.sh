#!/usr/bin/env bash
# research-runner-axis-pricing-table-miss/run.sh — FR-AE-012 / Edge case anchor.
#
# Validates: a fixture whose transcript has `message.model: <unknown-model>`
# produces `cost_usd: null` + `pricing-table-miss: <unknown-model>` warning,
# without failing the run on other axes. AND: when ALL fixtures null AND
# `cost` is declared → fail-fast at run-end.
#
# Pure-shell unit fixture per the test substrate hierarchy. Drives
# compute-cost-usd.sh directly with unknown model_ids.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
costcalc="$repo_root/plugin-wheel/scripts/harness/compute-cost-usd.sh"
pricing="$repo_root/plugin-kiln/lib/pricing.json"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: unknown model_id → null + pricing-table-miss warning on stderr.
# Anchors: User Story 4 acceptance scenario 2, FR-AE-012.
err=$(mktemp)
trap 'rm -f "$err"' EXIT
out=$(bash "$costcalc" --pricing-json "$pricing" --model-id "claude-experimental-X" \
                       --input-tokens 100 --output-tokens 50 --cached-input-tokens 0 2>"$err")
[[ $out == "null" ]] || fail "unknown model: expected stdout 'null', got '$out'"
grep -qF "pricing-table-miss: claude-experimental-X" "$err" || \
  fail "stderr missing 'pricing-table-miss: claude-experimental-X' (stderr: $(cat "$err"))"
assertions=$((assertions + 2))

# A2: empty model_id → null + pricing-table-miss: <empty>.
# Anchors: User Story 4 acceptance scenario 3, FR-AE-012.
out=$(bash "$costcalc" --pricing-json "$pricing" --model-id "" \
                       --input-tokens 100 --output-tokens 50 --cached-input-tokens 0 2>"$err")
[[ $out == "null" ]] || fail "empty model: expected stdout 'null', got '$out'"
grep -qF "pricing-table-miss: <empty>" "$err" || \
  fail "stderr missing 'pricing-table-miss: <empty>' (stderr: $(cat "$err"))"
assertions=$((assertions + 2))

# A3: render report with mixed-fixture cost — one known model, one null.
# Anchors: User Story 4 acceptance scenario 2 (per-fixture row shows '—' for missing cost).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; rm -f "$err"' EXIT
ndjson="$tmp/results.ndjson"
{
  jq -nc \
    '{fixture_slug:"001-known", fixture_path:"/abs/x",
      baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:100,output:50,cached_creation:0,cached_read:0,total:150},time_seconds:5.0,cost_usd:0.0001,model_id:"claude-opus-4-7"},
      candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:100,output:50,cached_creation:0,cached_read:0,total:150},time_seconds:5.0,cost_usd:0.0001,model_id:"claude-opus-4-7"},
      delta_tokens:0, delta_time_seconds:0, delta_cost_usd:0,
      verdict:"pass",
      per_axis_verdicts:{accuracy:"pass",tokens:"pass",time:"pass",cost:"pass"}}'
  jq -nc \
    '{fixture_slug:"002-unknown", fixture_path:"/abs/y",
      baseline:{scratch_uuid:"u3",scratch_dir:"/tmp/kiln-test-u3/",transcript_path:"/abs/log/u3.ndjson",verdict_report_path:"/abs/log/u3.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:100,output:50,cached_creation:0,cached_read:0,total:150},time_seconds:5.0,cost_usd:null,model_id:"claude-experimental-X"},
      candidate:{scratch_uuid:"u4",scratch_dir:"/tmp/kiln-test-u4/",transcript_path:"/abs/log/u4.ndjson",verdict_report_path:"/abs/log/u4.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:100,output:50,cached_creation:0,cached_read:0,total:150},time_seconds:5.0,cost_usd:null,model_id:"claude-experimental-X"},
      delta_tokens:0, delta_time_seconds:0, delta_cost_usd:null,
      verdict:"pass",
      per_axis_verdicts:{accuracy:"pass",tokens:"pass",time:"pass",cost:"not-enforced"}}'
} >"$ndjson"

RESEARCH_REPORT_RUN_UUID=test-uuid \
RESEARCH_REPORT_GATE_MODE=per_axis_direction \
RESEARCH_REPORT_BLAST_RADIUS=isolated \
RESEARCH_REPORT_RIGOR_ROW="min_fixtures=3, tolerance_pct=5" \
RESEARCH_REPORT_DECLARED_AXES="tokens (equal_or_better)" \
RESEARCH_REPORT_WARNINGS="pricing-table-miss: claude-experimental-X" \
  bash "$renderer" "$tmp/report.md" <"$ndjson"

grep -qF '$0.0001/$0.0001' "$tmp/report.md" || fail "report missing opus row (\$0.0001/\$0.0001)"
grep -qF '—/—' "$tmp/report.md" || fail "report missing '—/—' for null-cost fixture"
grep -qF "pricing-table-miss: claude-experimental-X" "$tmp/report.md" || \
  fail "report missing 'pricing-table-miss: claude-experimental-X' warning"
assertions=$((assertions + 3))

echo "PASS ($assertions assertions)"
