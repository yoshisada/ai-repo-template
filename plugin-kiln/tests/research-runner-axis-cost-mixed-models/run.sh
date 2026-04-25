#!/usr/bin/env bash
# research-runner-axis-cost-mixed-models/run.sh — SC-AE-004 anchor.
#
# Validates User Story 4 (FR-AE-011, FR-AE-012):
# A research run on a corpus mixing fixtures from `claude-opus-4-7` and
# `claude-haiku-4-5-20251001` MUST produce per-fixture `cost_usd` values
# matching `(in × $/in + out × $/out + cached × $/cached) / 1_000_000` to
# 4 decimal places using RECONCILED 2026-04-25 pricing (opus 5/25/0.5,
# haiku 1/5/0.1).
#
# Pure-shell unit fixture per the test substrate hierarchy. Drives
# compute-cost-usd.sh directly with hand-computed token tuples + verifies
# the output to 4dp.
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
costcalc="$repo_root/plugin-wheel/scripts/harness/compute-cost-usd.sh"
pricing="$repo_root/plugin-kiln/lib/pricing.json"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: pricing.json exists and contains the three reconciled rows.
# Anchors: FR-AE-010, contracts §8 RECONCILED 2026-04-25.
[[ -f $pricing ]] || fail "pricing.json missing: $pricing"
opus_in=$(jq -r '."claude-opus-4-7".input_per_mtok' "$pricing")
opus_out=$(jq -r '."claude-opus-4-7".output_per_mtok' "$pricing")
opus_cached=$(jq -r '."claude-opus-4-7".cached_input_per_mtok' "$pricing")
[[ $opus_in == "5" || $opus_in == "5.0" || $opus_in == "5.00" ]] || fail "opus input rate unexpected: $opus_in (expected 5)"
[[ $opus_out == "25" || $opus_out == "25.0" || $opus_out == "25.00" ]] || fail "opus output rate unexpected: $opus_out (expected 25)"
[[ $opus_cached == "0.5" || $opus_cached == "0.50" ]] || fail "opus cached rate unexpected: $opus_cached (expected 0.5)"
haiku_in=$(jq -r '."claude-haiku-4-5-20251001".input_per_mtok' "$pricing")
[[ $haiku_in == "1" || $haiku_in == "1.0" || $haiku_in == "1.00" ]] || fail "haiku input rate unexpected: $haiku_in (expected 1)"
assertions=$((assertions + 4))

# A2: opus cost — 1000 in, 500 out, 0 cached.
# Hand-computed: (1000*5 + 500*25 + 0*0.5)/1_000_000 = (5000+12500+0)/1e6 = 0.0175
# Anchors: User Story 4 acceptance scenario 1 (4dp precision).
cost=$(bash "$costcalc" --pricing-json "$pricing" --model-id "claude-opus-4-7" \
                       --input-tokens 1000 --output-tokens 500 --cached-input-tokens 0)
[[ $cost == "0.0175" ]] || fail "opus 1000/500/0 expected 0.0175, got $cost"
assertions=$((assertions + 1))

# A3: haiku cost — 2000 in, 1000 out, 500 cached.
# Hand-computed: (2000*1 + 1000*5 + 500*0.1)/1_000_000 = (2000+5000+50)/1e6 = 0.0071 (0.00705 → 0.0071? printf %.4f rounds half-to-even)
# 7050/1000000 = 0.00705 → printf "%.4f" → 0.0070 or 0.0071 (banker's rounding).
cost=$(bash "$costcalc" --pricing-json "$pricing" --model-id "claude-haiku-4-5-20251001" \
                       --input-tokens 2000 --output-tokens 1000 --cached-input-tokens 500)
# Accept either 0.0070 or 0.0071 depending on awk's printf rounding behavior.
[[ $cost == "0.0071" || $cost == "0.0070" ]] || fail "haiku 2000/1000/500 expected ~0.00705, got $cost"
assertions=$((assertions + 1))

# A4: opus cost with cached input — 100 in, 50 out, 1000 cached.
# Hand-computed: (100*5 + 50*25 + 1000*0.5)/1e6 = (500+1250+500)/1e6 = 0.0023 (2250/1e6 = 0.00225 → 0.0022 or 0.0023)
cost=$(bash "$costcalc" --pricing-json "$pricing" --model-id "claude-opus-4-7" \
                       --input-tokens 100 --output-tokens 50 --cached-input-tokens 1000)
[[ $cost == "0.0023" || $cost == "0.0022" ]] || fail "opus 100/50/1000 expected ~0.00225, got $cost"
assertions=$((assertions + 1))

# A5: synthesize mixed-model NDJSON + drive renderer.
# Anchors: User Story 4 acceptance scenario 1 (mixed corpus + per-fixture cost in report).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ndjson="$tmp/results.ndjson"
{
  jq -nc \
    '{fixture_slug:"001-opus-fixture", fixture_path:"/abs/x",
      baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:1000,output:500,cached_creation:0,cached_read:0,total:1500},time_seconds:5.0,cost_usd:0.0175,model_id:"claude-opus-4-7"},
      candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:1000,output:500,cached_creation:0,cached_read:0,total:1500},time_seconds:5.0,cost_usd:0.0175,model_id:"claude-opus-4-7"},
      delta_tokens:0, delta_time_seconds:0, delta_cost_usd:0,
      verdict:"pass",
      per_axis_verdicts:{accuracy:"pass",tokens:"pass",time:"pass",cost:"pass"}}'
  jq -nc \
    '{fixture_slug:"002-haiku-fixture", fixture_path:"/abs/y",
      baseline:{scratch_uuid:"u3",scratch_dir:"/tmp/kiln-test-u3/",transcript_path:"/abs/log/u3.ndjson",verdict_report_path:"/abs/log/u3.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:2000,output:1000,cached_creation:0,cached_read:500,total:3500},time_seconds:5.0,cost_usd:0.0071,model_id:"claude-haiku-4-5-20251001"},
      candidate:{scratch_uuid:"u4",scratch_dir:"/tmp/kiln-test-u4/",transcript_path:"/abs/log/u4.ndjson",verdict_report_path:"/abs/log/u4.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:2000,output:1000,cached_creation:0,cached_read:500,total:3500},time_seconds:5.0,cost_usd:0.0071,model_id:"claude-haiku-4-5-20251001"},
      delta_tokens:0, delta_time_seconds:0, delta_cost_usd:0,
      verdict:"pass",
      per_axis_verdicts:{accuracy:"pass",tokens:"pass",time:"pass",cost:"pass"}}'
} >"$ndjson"

RESEARCH_REPORT_RUN_UUID=test-uuid \
RESEARCH_REPORT_GATE_MODE=per_axis_direction \
RESEARCH_REPORT_BLAST_RADIUS=isolated \
RESEARCH_REPORT_RIGOR_ROW="min_fixtures=3, tolerance_pct=5" \
RESEARCH_REPORT_DECLARED_AXES="cost (lower)" \
  bash "$renderer" "$tmp/report.md" <"$ndjson"

grep -qF '$0.0175/$0.0175' "$tmp/report.md" || fail "report missing opus cost \$0.0175/\$0.0175"
grep -qF '$0.0071/$0.0071' "$tmp/report.md" || fail "report missing haiku cost \$0.0071/\$0.0071"
assertions=$((assertions + 2))

echo "PASS ($assertions assertions)"
