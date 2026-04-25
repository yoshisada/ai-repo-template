#!/usr/bin/env bash
# research-runner.sh — Baseline-vs-candidate research substrate.
#
# Satisfies: FR-S-001 (two --plugin-dir args), FR-S-005 (strict gate),
#            FR-S-007 (standalone CLI), FR-S-008 (exit codes), FR-S-011
#            (per-arm scratch /tmp/kiln-test-<uuid>/), FR-S-012 (TAP v14
#            stdout), NFR-S-002 (no fork — sibling helpers untouched),
#            NFR-S-007 (concurrency-safety via UUID-namespaced paths).
# Contract:  specs/research-first-foundation/contracts/interfaces.md §2.
#
# Synopsis:
#   research-runner.sh --baseline <plugin-dir> --candidate <plugin-dir> \
#                      --corpus <corpus-dir> [--report-path <path>]
#
# Stdout: TAP v14 stream — header + one `ok|not ok` line per fixture per arm
#         + final aggregate-verdict comment + report-path comment.
# Stderr: diagnostics only.
# Exit:   0 — all fixtures pass; 1 — at least one regression; 2 — at least
#         one inconclusive (missing files, stalled, parse error, empty corpus).
set -euo pipefail
LC_ALL=C
export LC_ALL

harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$harness_dir/../../.." && pwd )

bail_out() {
  printf 'Bail out! %s\n' "$1"
  exit 2
}

# --- Parse args --------------------------------------------------------------
baseline_dir=
candidate_dir=
corpus_dir=
report_path=
while (( $# > 0 )); do
  case $1 in
    --baseline) baseline_dir=${2:-}; shift 2 ;;
    --candidate) candidate_dir=${2:-}; shift 2 ;;
    --corpus) corpus_dir=${2:-}; shift 2 ;;
    --report-path) report_path=${2:-}; shift 2 ;;
    --help|-h)
      sed -n '2,18p' "$0"; exit 0 ;;
    *) bail_out "unknown flag: $1" ;;
  esac
done

[[ -n $baseline_dir ]] || bail_out "missing required flag: --baseline"
[[ -n $candidate_dir ]] || bail_out "missing required flag: --candidate"
[[ -n $corpus_dir ]] || bail_out "missing required flag: --corpus"
[[ -d $baseline_dir ]] || bail_out "baseline plugin-dir not found: $baseline_dir"
[[ -d $candidate_dir ]] || bail_out "candidate plugin-dir not found: $candidate_dir"
[[ -d $corpus_dir ]] || bail_out "corpus dir not found: $corpus_dir"

# Absolutize paths so downstream helpers + report fields are stable.
baseline_dir=$( cd -- "$baseline_dir" && pwd )
candidate_dir=$( cd -- "$candidate_dir" && pwd )
corpus_dir=$( cd -- "$corpus_dir" && pwd )

# Check claude CLI (parity with wheel-test-runner FR-S-001 anchor).
if ! command -v claude >/dev/null 2>&1; then
  bail_out "claude CLI not on PATH; install Claude Code (https://docs.claude.com/en/docs/claude-code)"
fi

# --- Resolve report path -----------------------------------------------------
logs_dir="$repo_root/.kiln/logs"
mkdir -p "$logs_dir"

if [[ -z $report_path ]]; then
  run_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
  report_path="$logs_dir/research-${run_uuid}.md"
else
  run_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
fi

# --- Discover fixtures (deterministic order — Decision 4) -------------------
# FR-S-002: corpus layout <corpus-root>/<NNN-slug>/ — direct children of corpus_dir.
declare -a fixtures=()
while IFS= read -r -d '' dir; do
  fixtures+=("$dir")
done < <(find "$corpus_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

n=${#fixtures[@]}
(( n > 0 )) || bail_out "corpus contains zero fixtures"

# --- TAP header --------------------------------------------------------------
printf 'TAP version 14\n'
printf '1..%d\n' "$((n * 2))"

# --- Run loop ---------------------------------------------------------------
started_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
t_start=$(date +%s)

ndjson_results=$(mktemp)
trap 'rm -f "$ndjson_results"' EXIT

any_regression=0
any_inconclusive=0
tap_idx=0

run_arm() {
  # Run one fixture against one plugin-dir. Echoes JSON to stdout describing
  # the result. Always exits 0 from this function — failures are encoded in
  # the JSON, not via exit code (so the orchestrator can keep iterating).
  # Satisfies: FR-S-003 (per-arm metrics capture: assertion verdict + tokens).
  local fixture_dir=$1 plugin_dir=$2 arm=$3
  local slug=${fixture_dir##*/}
  local input_json="$fixture_dir/input.json"
  local expected_json="$fixture_dir/expected.json"

  if [[ ! -f $input_json ]]; then
    jq -nc --arg arm "$arm" --arg reason "missing-input-json" \
      '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:$reason, tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}}'
    return 0
  fi
  if [[ ! -f $expected_json ]]; then
    jq -nc --arg arm "$arm" --arg reason "missing-expected-json" \
      '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:$reason, tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}}'
    return 0
  fi

  # 1. Create scratch via existing helper (NFR-S-002 — invoked, not modified).
  local scratch_dir scratch_uuid
  if ! scratch_dir=$("$harness_dir/scratch-create.sh" 2>/dev/null); then
    jq -nc '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:"scratch-create-failed", tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}}'
    return 0
  fi
  scratch_uuid=${scratch_dir##*/kiln-test-}

  local transcript_path="$logs_dir/kiln-test-${scratch_uuid}-transcript.ndjson"
  local verdict_md_path="$logs_dir/kiln-test-${scratch_uuid}.md"
  : > "$transcript_path"

  # 2. Build initial-message-file from input.json (.message.content).
  local initial_msg_file="$scratch_dir/.research-initial-message.txt"
  local initial_msg
  if ! initial_msg=$(jq -r '.message.content' "$input_json" 2>/dev/null); then
    rm -rf "$scratch_dir"
    jq -nc '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:"malformed-input-json", tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}}'
    return 0
  fi
  printf '%s' "$initial_msg" > "$initial_msg_file"

  # 3. Run claude subprocess, redirecting stream-json to transcript.
  set +e
  ( cd "$scratch_dir" && \
    "$harness_dir/claude-invoke.sh" "$plugin_dir" "$scratch_dir" "$initial_msg_file" \
      > "$transcript_path" 2>/dev/null )
  local subprocess_exit=$?
  set -e

  # 4. Check assertion: simple `expected_exit_code` from expected.json.
  local expected_exit
  expected_exit=$(jq -r '.expected_exit_code // 0' "$expected_json")
  local assertion_pass=true
  if [[ $subprocess_exit -ne $expected_exit ]]; then
    assertion_pass=false
  fi

  # 5. Parse tokens.
  local tokens_line input_tok=0 output_tok=0 cc_tok=0 cr_tok=0 total_tok=0
  if tokens_line=$("$harness_dir/parse-token-usage.sh" "$transcript_path" 2>/dev/null); then
    read -r input_tok output_tok cc_tok cr_tok total_tok <<<"$tokens_line"
  else
    # Token parse failure — record inconclusive.
    jq -nc \
      --arg uuid "$scratch_uuid" \
      --arg dir "$scratch_dir/" \
      --arg tp "$transcript_path" \
      --arg vr "$verdict_md_path" \
      --arg reason "parse-error-${arm}" \
      '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:$uuid, scratch_dir:$dir, transcript_path:$tp, verdict_report_path:$vr, inconclusive_reason:$reason, tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}}'
    return 0
  fi

  # Cleanup scratch on success (matches kiln-test discipline).
  if [[ $assertion_pass == "true" ]]; then
    rm -rf "$scratch_dir"
  fi

  jq -nc \
    --arg uuid "$scratch_uuid" \
    --arg dir "$scratch_dir/" \
    --arg tp "$transcript_path" \
    --arg vr "$verdict_md_path" \
    --argjson ap "$assertion_pass" \
    --argjson ex "$subprocess_exit" \
    --argjson it "$input_tok" --argjson ot "$output_tok" \
    --argjson cc "$cc_tok" --argjson cr "$cr_tok" \
    --argjson tt "$total_tok" \
    '{assertion_pass:$ap, exit_code:$ex, stalled:false, scratch_uuid:$uuid, scratch_dir:$dir, transcript_path:$tp, verdict_report_path:$vr, tokens:{input:$it,output:$ot,cached_creation:$cc,cached_read:$cr,total:$tt}}'
}

# Strict-gate verdict per FR-S-005 (RECONCILED tolerance ±10 tokens band per NFR-S-001).
TOKEN_TOLERANCE=10
compute_verdict() {
  local b_pass=$1 c_pass=$2 b_tok=$3 c_tok=$4 b_inconc=$5 c_inconc=$6
  if [[ -n $b_inconc || -n $c_inconc ]]; then
    local reason
    if [[ -n $b_inconc ]]; then reason=$b_inconc; else reason=$c_inconc; fi
    printf 'inconclusive (%s)' "$reason"
    return
  fi
  local delta=$(( c_tok - b_tok ))
  local acc_reg=0 tok_reg=0
  if [[ $b_pass == "true" && $c_pass == "false" ]]; then acc_reg=1; fi
  if (( delta > TOKEN_TOLERANCE )); then tok_reg=1; fi
  if (( acc_reg == 1 && tok_reg == 1 )); then echo "regression (accuracy + tokens)"
  elif (( acc_reg == 1 )); then echo "regression (accuracy)"
  elif (( tok_reg == 1 )); then echo "regression (tokens)"
  else echo "pass"
  fi
}

for fixture_dir in "${fixtures[@]}"; do
  slug=${fixture_dir##*/}

  # Run baseline arm.
  baseline_json=$(run_arm "$fixture_dir" "$baseline_dir" "baseline")
  candidate_json=$(run_arm "$fixture_dir" "$candidate_dir" "candidate")

  b_pass=$(printf '%s' "$baseline_json" | jq -r '.assertion_pass')
  c_pass=$(printf '%s' "$candidate_json" | jq -r '.assertion_pass')
  b_tok=$(printf '%s' "$baseline_json" | jq -r '.tokens.total')
  c_tok=$(printf '%s' "$candidate_json" | jq -r '.tokens.total')
  b_inconc=$(printf '%s' "$baseline_json" | jq -r '.inconclusive_reason // ""')
  c_inconc=$(printf '%s' "$candidate_json" | jq -r '.inconclusive_reason // ""')

  verdict=$(compute_verdict "$b_pass" "$c_pass" "$b_tok" "$c_tok" "$b_inconc" "$c_inconc")
  delta=$(( c_tok - b_tok ))

  case $verdict in
    pass) ;;
    inconclusive*) any_inconclusive=1 ;;
    *) any_regression=1 ;;
  esac

  # Emit per-fixture NDJSON line (combining arms).
  jq -cn \
    --arg slug "$slug" \
    --arg fp "$fixture_dir" \
    --argjson b "$baseline_json" \
    --argjson c "$candidate_json" \
    --argjson dt "$delta" \
    --arg verdict "$verdict" \
    '{fixture_slug:$slug, fixture_path:$fp, baseline:$b, candidate:$c, delta_tokens:$dt, verdict:$verdict}' \
    >> "$ndjson_results"

  # Emit TAP — two lines per fixture (one per arm) per FR-S-012.
  tap_idx=$((tap_idx + 1))
  if [[ $b_pass == "true" && -z $b_inconc ]]; then
    printf 'ok %d - %s (baseline)\n' "$tap_idx" "$slug"
  else
    printf 'not ok %d - %s (baseline)\n' "$tap_idx" "$slug"
  fi
  tap_idx=$((tap_idx + 1))
  if [[ $c_pass == "true" && -z $c_inconc ]]; then
    printf 'ok %d - %s (candidate)\n' "$tap_idx" "$slug"
  else
    printf 'not ok %d - %s (candidate)\n' "$tap_idx" "$slug"
  fi
done

t_end=$(date +%s)
completed_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
wall_clock=$((t_end - t_start))

# --- Render report ----------------------------------------------------------
RESEARCH_REPORT_RUN_UUID="$run_uuid" \
RESEARCH_REPORT_BASELINE_PLUGIN_DIR="$baseline_dir" \
RESEARCH_REPORT_CANDIDATE_PLUGIN_DIR="$candidate_dir" \
RESEARCH_REPORT_CORPUS_DIR="$corpus_dir" \
RESEARCH_REPORT_STARTED="$started_iso" \
RESEARCH_REPORT_COMPLETED="$completed_iso" \
RESEARCH_REPORT_WALL_CLOCK="${wall_clock}s" \
  bash "$harness_dir/render-research-report.sh" "$report_path" < "$ndjson_results"

# --- Aggregate verdict ------------------------------------------------------
if (( any_regression > 0 )); then overall="FAIL"
elif (( any_inconclusive > 0 )); then overall="FAIL"
else overall="PASS"
fi

printf '# Aggregate verdict: %s\n' "$overall"
printf '# Report: %s\n' "$report_path"

if (( any_regression > 0 )); then exit 1; fi
if (( any_inconclusive > 0 )); then exit 2; fi
exit 0
