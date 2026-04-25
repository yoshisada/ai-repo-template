#!/usr/bin/env bash
# research-runner-determinism/run.sh — SC-S-006 + NFR-S-001 anchor.
#
# Validates: per-field token-count noise stays within ±10 absolute across
# rerun-equivalent transcripts, AND renderer is byte-deterministic given
# byte-identical input. Pure-shell fixture (no claude subprocess).
#
# Acceptance scenarios anchored:
# - SC-S-006: 3 reruns produce 3 byte-identical reports modulo the §8
#   timestamp-modulo-list, AND token observations within ±10 per-field.
# - NFR-S-001 reconciled tolerance: ±10 tokens absolute per `usage` field
#   (anchored to research.md §NFR-001 directive 2 — observed +3 wobble on
#   the lightest probe; ±10 covers with headroom).
set -euo pipefail

here=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$here/../../.." && pwd )
parser="$repo_root/plugin-wheel/scripts/harness/parse-token-usage.sh"
renderer="$repo_root/plugin-wheel/scripts/harness/render-research-report.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

assertions=0
fail() { echo "FAIL: $*"; exit 1; }

# A1: parse two rerun-equivalent transcripts (research.md §NFR-001 captured
# real numbers from two consecutive runs of kiln:kiln-version on the same
# commit + plugin-dir; observed +3 wobble on output_tokens and +3 on
# cache_creation_input_tokens). NFR-S-001 reconciled tolerance is ±10/field.
read -r ai ao acc acr atotal < <(bash "$parser" "$here/fixtures/transcript-A.ndjson")
read -r bi bo bcc bcr btotal < <(bash "$parser" "$here/fixtures/transcript-B.ndjson")
assertions=$((assertions + 2))

abs() { local x=$1; (( x < 0 )) && x=$(( -x )); echo "$x"; }
delta_input=$(abs $(( bi - ai )))
delta_output=$(abs $(( bo - ao )))
delta_cc=$(abs $(( bcc - acc )))
delta_cr=$(abs $(( bcr - acr )))

# A2..A5: each per-field delta MUST be ≤ 10 (NFR-S-001 reconciled).
(( delta_input <= 10 )) || fail "input_tokens delta=$delta_input exceeds ±10"
(( delta_output <= 10 )) || fail "output_tokens delta=$delta_output exceeds ±10"
(( delta_cc <= 10 )) || fail "cache_creation_input_tokens delta=$delta_cc exceeds ±10"
(( delta_cr <= 10 )) || fail "cache_read_input_tokens delta=$delta_cr exceeds ±10"
assertions=$((assertions + 4))

# A6: renderer determinism — same NDJSON input MUST produce byte-identical
# output (modulo timestamp-modulo-list, all caller-supplied env vars).
# Anchored to: SC-S-006, contracts §8 modulo-list.
ndjson="$tmp/in.ndjson"
jq -nc '
  {fixture_slug:"001-stable", fixture_path:"/abs/x",
    baseline:{scratch_uuid:"u1",scratch_dir:"/tmp/kiln-test-u1/",transcript_path:"/abs/log/u1.ndjson",verdict_report_path:"/abs/log/u1.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:12,output:492,cached_creation:14278,cached_read:113842,total:128624}},
    candidate:{scratch_uuid:"u2",scratch_dir:"/tmp/kiln-test-u2/",transcript_path:"/abs/log/u2.ndjson",verdict_report_path:"/abs/log/u2.md",assertion_pass:true,exit_code:0,stalled:false,tokens:{input:12,output:495,cached_creation:14281,cached_read:113842,total:128630}},
    delta_tokens:6, verdict:"pass"}' > "$ndjson"

export RESEARCH_REPORT_RUN_UUID=stable-uuid
export RESEARCH_REPORT_BASELINE_PLUGIN_DIR=/abs/baseline
export RESEARCH_REPORT_CANDIDATE_PLUGIN_DIR=/abs/candidate
export RESEARCH_REPORT_CORPUS_DIR=/abs/corpus
export RESEARCH_REPORT_STARTED=2026-04-25T00:00:00Z
export RESEARCH_REPORT_COMPLETED=2026-04-25T00:00:01Z
export RESEARCH_REPORT_WALL_CLOCK=1.0s

# Run 3 times, compare hashes.
for i in 1 2 3; do
  bash "$renderer" "$tmp/r${i}.md" < "$ndjson"
done
hash1=$(shasum -a 256 "$tmp/r1.md" | awk '{print $1}')
hash2=$(shasum -a 256 "$tmp/r2.md" | awk '{print $1}')
hash3=$(shasum -a 256 "$tmp/r3.md" | awk '{print $1}')
[[ $hash1 == "$hash2" && $hash2 == "$hash3" ]] || \
  fail "renderer not byte-deterministic across reruns ($hash1 / $hash2 / $hash3)"
assertions=$((assertions + 1))

# A7: run-level verdict is stable PASS (delta=6, comfortably below ±10 band).
# Anchored to: NFR-S-001 "load-bearing determinism" — pass/fail verdict stability.
grep -qE 'Overall\*?\*?: PASS' "$tmp/r1.md" || fail "run-level verdict not PASS"
assertions=$((assertions + 1))

echo "PASS ($assertions assertions)"
