#!/usr/bin/env bash
# research-runner.sh — Baseline-vs-candidate research substrate.
#
# Foundation satisfies: FR-S-001 (two --plugin-dir args), FR-S-005 (strict
#   gate), FR-S-007 (standalone CLI), FR-S-008 (exit codes), FR-S-011
#   (per-arm scratch /tmp/kiln-test-<uuid>/), FR-S-012 (TAP v14 stdout),
#   NFR-S-002 (no fork — sibling helpers untouched), NFR-S-007 (concurrency-
#   safety via UUID-namespaced paths).
# Foundation contract:  specs/research-first-foundation/contracts/interfaces.md §2.
#
# Axis-enrichment EXTENDS foundation with:
#   FR-AE-001 (empirical_quality declaration parsing via parse-prd-frontmatter.sh)
#   FR-AE-002/FR-AE-005 (per-axis direction enforcement via evaluate-direction.sh)
#   FR-AE-004 (blast_radius → research-rigor.json lookup, min_fixtures fail-fast)
#   FR-AE-006/FR-AE-007 (excluded_fixtures + excluded-fraction-high warning)
#   FR-AE-008 (foundation strict-gate fall-through codepath when --prd absent OR
#     PRD has no empirical_quality:)
#   FR-AE-009 (time_seconds via monotonic clock — resolve-monotonic-clock.sh)
#   FR-AE-011/FR-AE-012 (cost_usd via compute-cost-usd.sh + pricing-table-miss)
#   FR-AE-014 (all four axes always measured + populated; gate-enforcement
#     opt-in via empirical_quality:)
#   NFR-AE-001 (sub-second-fixture guard for time axis)
#   NFR-AE-003 (backward compat — foundation strict gate path preserved)
#   NFR-AE-005 (atomic pairing — co-ships rigor + pricing config files)
#   NFR-AE-006 (monotonic-clock probe ladder)
#   NFR-AE-007 (loud-failure on config malformation)
# Axis-enrichment contract: specs/research-first-axis-enrichment/contracts/interfaces.md §2.
#
# Synopsis:
#   research-runner.sh --baseline <plugin-dir> --candidate <plugin-dir> \
#                      --corpus <corpus-dir> [--prd <path>] [--report-path <path>]
#
# Stdout: TAP v14 stream — header + one `ok|not ok` line per fixture per arm
#         + final aggregate-verdict comment + report-path comment.
# Stderr: diagnostics only.
# Exit:   0 — all fixtures pass; 1 — at least one regression; 2 — at least
#         one inconclusive (missing files, stalled, parse error, empty corpus,
#         min-fixtures-not-met, malformed config, unknown enum, etc.).
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
prd_path=
while (( $# > 0 )); do
  case $1 in
    --baseline) baseline_dir=${2:-}; shift 2 ;;
    --candidate) candidate_dir=${2:-}; shift 2 ;;
    --corpus) corpus_dir=${2:-}; shift 2 ;;
    --report-path) report_path=${2:-}; shift 2 ;;
    --prd) prd_path=${2:-}; shift 2 ;;
    --help|-h)
      sed -n '2,42p' "$0"; exit 0 ;;
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

# --- AE: --prd validation + frontmatter parse (FR-AE-001) -------------------
prd_frontmatter='{}'
if [[ -n $prd_path ]]; then
  [[ -f $prd_path ]] || bail_out "--prd path not found: $prd_path"
  prd_path=$( cd -- "$( dirname -- "$prd_path" )" && pwd )/$( basename -- "$prd_path" )
  if ! prd_frontmatter=$("$harness_dir/parse-prd-frontmatter.sh" "$prd_path" 2>&1); then
    # parse-prd-frontmatter.sh emits its own `Bail out!` line on stderr; surface verbatim.
    printf '%s\n' "$prd_frontmatter"
    exit 2
  fi
fi

# Extract frontmatter fields (null when absent — caller distinguishes).
prd_empirical_quality=$(printf '%s' "$prd_frontmatter" | jq -c '.empirical_quality // null')
prd_blast_radius=$(printf '%s' "$prd_frontmatter" | jq -r '.blast_radius // ""')
prd_excluded_fixtures=$(printf '%s' "$prd_frontmatter" | jq -c '.excluded_fixtures // []')

# Gate-mode dispatch (FR-AE-008):
#   gate_mode=foundation_strict — --prd omitted OR PRD has no empirical_quality:
#   gate_mode=per_axis_direction — --prd provided AND empirical_quality is non-null
if [[ -z $prd_path || $prd_empirical_quality == "null" ]]; then
  gate_mode="foundation_strict"
else
  gate_mode="per_axis_direction"
fi

# --- AE: Resolve rigor row (FR-AE-004 / NFR-AE-007) -------------------------
# Always required when gate_mode=per_axis_direction. Even in foundation_strict,
# we read the file if present (loud-failure is a structural property).
rigor_json="$repo_root/plugin-kiln/lib/research-rigor.json"
min_fixtures=
tolerance_pct=
if [[ $gate_mode == "per_axis_direction" ]]; then
  [[ -f $rigor_json ]] || bail_out "research-rigor.json malformed-or-missing: $rigor_json not found"
  if ! rigor_err=$(jq -e . "$rigor_json" 2>&1 >/dev/null); then
    bail_out "research-rigor.json malformed-or-missing: $rigor_err"
  fi
  case $prd_blast_radius in
    isolated|feature|cross-cutting|infra) ;;
    "") bail_out "PRD missing blast_radius: (required when empirical_quality: declared)" ;;
    *) bail_out "unknown blast_radius: $prd_blast_radius (allowed: isolated|feature|cross-cutting|infra)" ;;
  esac
  rigor_row=$(jq -c --arg r "$prd_blast_radius" '.[$r]' "$rigor_json")
  [[ $rigor_row != "null" && -n $rigor_row ]] || bail_out "research-rigor.json missing key: $prd_blast_radius"
  min_fixtures=$(printf '%s' "$rigor_row" | jq -r '.min_fixtures')
  tolerance_pct=$(printf '%s' "$rigor_row" | jq -r '.tolerance_pct')
  [[ $min_fixtures =~ ^[0-9]+$ ]] || bail_out "research-rigor.json malformed-or-missing: min_fixtures not int for $prd_blast_radius"
  [[ $tolerance_pct =~ ^[0-9]+$ ]] || bail_out "research-rigor.json malformed-or-missing: tolerance_pct not int for $prd_blast_radius"
fi

# --- AE: Resolve pricing table (FR-AE-010 + edge cases) ---------------------
pricing_json="$repo_root/plugin-kiln/lib/pricing.json"
pricing_present=0
if [[ -f $pricing_json ]]; then
  if ! pricing_err=$(jq -e . "$pricing_json" 2>&1 >/dev/null); then
    bail_out "pricing.json malformed: $pricing_err"
  fi
  pricing_present=1
fi

# If cost is declared in empirical_quality but pricing.json is missing →
# fail-fast at startup.
declare -a declared_metrics=()
if [[ $gate_mode == "per_axis_direction" ]]; then
  while IFS= read -r m; do declared_metrics+=("$m"); done < <(printf '%s' "$prd_empirical_quality" | jq -r '.[].metric')
  for m in "${declared_metrics[@]}"; do
    if [[ $m == "cost" && $pricing_present -eq 0 ]]; then
      bail_out "cost axis declared but plugin-kiln/lib/pricing.json not found"
    fi
  done
fi

# Check claude CLI (parity with wheel-test-runner FR-S-001 anchor).
if ! command -v claude >/dev/null 2>&1; then
  bail_out "claude CLI not on PATH; install Claude Code (https://docs.claude.com/en/docs/claude-code)"
fi

# --- AE: Resolve monotonic clock (FR-AE-009 / NFR-AE-006) -------------------
if ! mono_invocation=$("$harness_dir/resolve-monotonic-clock.sh" 2>&1); then
  printf '%s\n' "$mono_invocation"
  exit 2
fi
# mono_invocation is the resolved invocation string; eval it to read time.
mono_read() { eval "$mono_invocation"; }

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
declare -a fixtures_all=()
while IFS= read -r -d '' dir; do
  fixtures_all+=("$dir")
done < <(find "$corpus_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

n_all=${#fixtures_all[@]}
(( n_all > 0 )) || bail_out "corpus contains zero fixtures"

# --- AE: Apply excluded_fixtures (FR-AE-006) --------------------------------
# Build set of excluded slugs; verify each path exists in corpus.
declare -a excluded_slugs=()
declare -a excluded_reasons=()
if [[ $prd_excluded_fixtures != "[]" && $prd_excluded_fixtures != "null" ]]; then
  while IFS=$'\t' read -r ex_path ex_reason; do
    [[ -n $ex_path ]] || continue
    # Verify path exists in corpus.
    found=0
    for fd in "${fixtures_all[@]}"; do
      if [[ "${fd##*/}" == "$ex_path" ]]; then found=1; break; fi
    done
    (( found == 1 )) || bail_out "excluded_fixtures path not found in corpus: $ex_path"
    excluded_slugs+=("$ex_path")
    excluded_reasons+=("$ex_reason")
  done < <(printf '%s' "$prd_excluded_fixtures" | jq -r '.[] | [.path, .reason] | @tsv')
fi
n_excluded=${#excluded_slugs[@]}

# Filter out excluded fixtures.
declare -a fixtures=()
for fd in "${fixtures_all[@]}"; do
  slug=${fd##*/}
  is_excluded=0
  for ex in "${excluded_slugs[@]}"; do
    if [[ $ex == "$slug" ]]; then is_excluded=1; break; fi
  done
  (( is_excluded == 0 )) && fixtures+=("$fd")
done
n=${#fixtures[@]}

# --- AE: min_fixtures fail-fast (FR-AE-004 / SC-AE-002) ---------------------
if [[ $gate_mode == "per_axis_direction" ]]; then
  if (( n < min_fixtures )); then
    if (( n_excluded > 0 )); then
      bail_out "min-fixtures-not-met: $n < $min_fixtures (blast_radius: $prd_blast_radius, $n_excluded fixtures excluded)"
    else
      bail_out "min-fixtures-not-met: $n < $min_fixtures (blast_radius: $prd_blast_radius)"
    fi
  fi
fi

# --- TAP header --------------------------------------------------------------
printf 'TAP version 14\n'
printf '1..%d\n' "$((n * 2))"

# --- Run loop ---------------------------------------------------------------
started_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
t_start=$(date +%s)

ndjson_results=$(mktemp)
warnings_file=$(mktemp)
trap 'rm -f "$ndjson_results" "$warnings_file"' EXIT
: >"$warnings_file"

any_regression=0
any_inconclusive=0
tap_idx=0

# extract_model_id <transcript-path>: emit message.model from the LAST
# stream-json envelope of type=assistant containing a non-null model. Empty
# string if absent.
extract_model_id() {
  local transcript=$1
  [[ -f $transcript ]] || { printf ''; return 0; }
  awk '
    /"type":"assistant"/ { last = $0 }
    END { if (last) print last }
  ' "$transcript" | jq -r '.message.model // empty' 2>/dev/null || true
}

run_arm() {
  # Run one fixture against one plugin-dir. Echoes JSON to stdout describing
  # the result. Always exits 0 from this function — failures are encoded in
  # the JSON, not via exit code (so the orchestrator can keep iterating).
  # Satisfies: FR-S-003 (per-arm metrics capture) + FR-AE-009 (time) + FR-AE-011/012 (cost).
  local fixture_dir=$1 plugin_dir=$2 arm=$3
  local slug=${fixture_dir##*/}
  local input_json="$fixture_dir/input.json"
  local expected_json="$fixture_dir/expected.json"

  if [[ ! -f $input_json ]]; then
    jq -nc --arg arm "$arm" --arg reason "missing-input-json" \
      '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:$reason, tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}, time_seconds:0, cost_usd:null, model_id:null}'
    return 0
  fi
  if [[ ! -f $expected_json ]]; then
    jq -nc --arg arm "$arm" --arg reason "missing-expected-json" \
      '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:$reason, tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}, time_seconds:0, cost_usd:null, model_id:null}'
    return 0
  fi

  # 1. Create scratch via existing helper (NFR-S-002 — invoked, not modified).
  local scratch_dir scratch_uuid
  if ! scratch_dir=$("$harness_dir/scratch-create.sh" 2>/dev/null); then
    jq -nc '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:"scratch-create-failed", tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}, time_seconds:0, cost_usd:null, model_id:null}'
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
    jq -nc '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:"", scratch_dir:"", transcript_path:"", verdict_report_path:"", inconclusive_reason:"malformed-input-json", tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}, time_seconds:0, cost_usd:null, model_id:null}'
    return 0
  fi
  printf '%s' "$initial_msg" > "$initial_msg_file"

  # 3. Run claude subprocess, redirecting stream-json to transcript.
  #    AE: time_seconds capture via monotonic clock (FR-AE-009).
  local t0 t1 time_seconds
  t0=$(mono_read)
  set +e
  ( cd "$scratch_dir" && \
    "$harness_dir/claude-invoke.sh" "$plugin_dir" "$scratch_dir" "$initial_msg_file" \
      > "$transcript_path" 2>/dev/null )
  local subprocess_exit=$?
  set -e
  t1=$(mono_read)
  time_seconds=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.4f", b - a }')

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
      --argjson ts "$time_seconds" \
      '{assertion_pass:false, exit_code:2, stalled:false, scratch_uuid:$uuid, scratch_dir:$dir, transcript_path:$tp, verdict_report_path:$vr, inconclusive_reason:$reason, tokens:{input:0,output:0,cached_creation:0,cached_read:0,total:0}, time_seconds:$ts, cost_usd:null, model_id:null}'
    return 0
  fi

  # 6. AE: derive cost_usd via compute-cost-usd.sh (FR-AE-011 / FR-AE-012).
  local model_id cost_usd cached_input_total
  model_id=$(extract_model_id "$transcript_path")
  cached_input_total=$(( cc_tok + cr_tok ))
  cost_usd="null"
  local cost_warn_file
  cost_warn_file=$(mktemp)
  if (( pricing_present == 1 )); then
    local cost_out
    if cost_out=$("$harness_dir/compute-cost-usd.sh" \
        --pricing-json "$pricing_json" \
        --model-id "$model_id" \
        --input-tokens "$input_tok" \
        --output-tokens "$output_tok" \
        --cached-input-tokens "$cached_input_total" 2>"$cost_warn_file"); then
      cost_usd=$cost_out
      # Surface model-miss warning verbatim from stderr to global warnings file.
      if [[ -s $cost_warn_file ]]; then
        sed -n 's/^pricing-table-miss: \(.*\)$/pricing-table-miss: \1/p' "$cost_warn_file" >>"$warnings_file"
      fi
    else
      rm -f "$cost_warn_file"
      bail_out "compute-cost-usd.sh failed"
    fi
  fi
  rm -f "$cost_warn_file"

  # Cleanup scratch on success (matches kiln-test discipline).
  if [[ $assertion_pass == "true" ]]; then
    rm -rf "$scratch_dir"
  fi

  # Convert cost_usd: numeric string → number; "null" → JSON null.
  local cost_jq_arg
  if [[ $cost_usd == "null" ]]; then
    cost_jq_arg=null
  else
    cost_jq_arg=$cost_usd
  fi
  local model_jq
  if [[ -z $model_id ]]; then model_jq=null; else model_jq=$(jq -nc --arg m "$model_id" '$m'); fi

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
    --argjson ts "$time_seconds" \
    --argjson cu "$cost_jq_arg" \
    --argjson mid "$model_jq" \
    '{assertion_pass:$ap, exit_code:$ex, stalled:false, scratch_uuid:$uuid, scratch_dir:$dir, transcript_path:$tp, verdict_report_path:$vr, tokens:{input:$it,output:$ot,cached_creation:$cc,cached_read:$cr,total:$tt}, time_seconds:$ts, cost_usd:$cu, model_id:$mid}'
}

# --- Foundation strict-gate verdict (FR-AE-008 fall-through path) ----------
# Per spec.md / contracts.md / Decision 7: when --prd is omitted OR PRD has
# no empirical_quality:, take an EXPLICIT codepath that bypasses
# evaluate-direction.sh. Foundation's hardcoded multiplicative 1.5x band.
TOKEN_TOLERANCE_MULTIPLIER_NUM=15
TOKEN_TOLERANCE_MULTIPLIER_DEN=10  # 15/10 = 1.5x
compute_verdict_strict() {
  local b_pass=$1 c_pass=$2 b_tok=$3 c_tok=$4 b_inconc=$5 c_inconc=$6
  if [[ -n $b_inconc || -n $c_inconc ]]; then
    local reason
    if [[ -n $b_inconc ]]; then reason=$b_inconc; else reason=$c_inconc; fi
    printf 'inconclusive (%s)' "$reason"
    return
  fi
  local acc_reg=0 tok_reg=0
  if [[ $b_pass == "true" && $c_pass == "false" ]]; then acc_reg=1; fi
  if (( b_tok == 0 )); then
    (( c_tok > 0 )) && tok_reg=1
  elif (( c_tok * TOKEN_TOLERANCE_MULTIPLIER_DEN > b_tok * TOKEN_TOLERANCE_MULTIPLIER_NUM )); then
    tok_reg=1
  fi
  if (( acc_reg == 1 && tok_reg == 1 )); then echo "regression (accuracy + tokens)"
  elif (( acc_reg == 1 )); then echo "regression (accuracy)"
  elif (( tok_reg == 1 )); then echo "regression (tokens)"
  else echo "pass"
  fi
}

# --- AE: Per-axis direction verdict (FR-AE-002 / FR-AE-005 / FR-AE-014) ----
# Iterates over declared axes; emits a per-axis verdicts JSON object plus an
# overall verdict string. Sub-second guard (NFR-AE-001) silently un-enforces
# time on fixtures with median wall-clock < 1.0s.
compute_verdict_per_axis() {
  local b_pass=$1 c_pass=$2 b_tok=$3 c_tok=$4 b_inconc=$5 c_inconc=$6
  local b_time=$7 c_time=$8 b_cost=$9 c_cost=${10}
  local slug=${11}

  if [[ -n $b_inconc || -n $c_inconc ]]; then
    local reason
    if [[ -n $b_inconc ]]; then reason=$b_inconc; else reason=$c_inconc; fi
    # Emit JSON envelope: per_axis_verdicts and verdict.
    jq -nc --arg v "inconclusive ($reason)" \
      '{per_axis_verdicts:{accuracy:"not-enforced"}, verdict:$v}'
    return
  fi

  # accuracy is always implicitly enforced equal_or_better (FR-AE-002).
  local b_acc=0 c_acc=0
  [[ $b_pass == "true" ]] && b_acc=1
  [[ $c_pass == "true" ]] && c_acc=1
  local acc_verdict
  acc_verdict=$("$harness_dir/evaluate-direction.sh" \
    --axis accuracy --direction equal_or_better --tolerance-pct 0 \
    --baseline "$b_acc" --candidate "$c_acc")

  # Build per-axis verdicts table — start with accuracy, fill all four axes.
  declare -A pav
  pav[accuracy]=$acc_verdict
  pav[tokens]="not-enforced"
  pav[time]="not-enforced"
  pav[cost]="not-enforced"

  # Sub-second guard: compute median wall-clock across baseline + candidate.
  # Median of two = average of the two values.
  local median_time
  median_time=$(awk -v a="$b_time" -v b="$c_time" 'BEGIN { printf "%.4f", (a + b) / 2.0 }')
  local time_below_floor=0
  if awk -v m="$median_time" 'BEGIN { exit (m < 1.0) ? 0 : 1 }'; then
    time_below_floor=1
  fi

  # Iterate over declared axes.
  local declared_json=$prd_empirical_quality
  local n_axes
  n_axes=$(printf '%s' "$declared_json" | jq 'length')
  local i
  for (( i=0; i < n_axes; i++ )); do
    local metric direction
    metric=$(printf '%s' "$declared_json" | jq -r ".[$i].metric")
    direction=$(printf '%s' "$declared_json" | jq -r ".[$i].direction")

    case $metric in
      output_quality)
        # Reserved for step 5 — emit warning + ignore (per FR-AE-001 / spec edge cases).
        printf 'output-quality-reserved: ignoring declared output_quality (reserved for step 5)\n' >>"$warnings_file"
        continue
        ;;
      accuracy)
        # accuracy is always enforced; if user re-declares, just keep current verdict.
        continue
        ;;
      tokens)
        pav[tokens]=$("$harness_dir/evaluate-direction.sh" \
          --axis tokens --direction "$direction" --tolerance-pct "$tolerance_pct" \
          --baseline "$b_tok" --candidate "$c_tok")
        ;;
      time)
        if (( time_below_floor == 1 )); then
          # NFR-AE-001 sub-second guard — silently un-enforce + emit warning.
          printf 'time-axis-skipped: %s wall-clock %.1fs below 1.0s floor\n' "$slug" "$median_time" >>"$warnings_file"
          pav[time]="not-enforced"
        else
          pav[time]=$("$harness_dir/evaluate-direction.sh" \
            --axis time --direction "$direction" --tolerance-pct "$tolerance_pct" \
            --baseline "$b_time" --candidate "$c_time")
        fi
        ;;
      cost)
        if [[ $b_cost == "null" || $c_cost == "null" ]]; then
          # Cost null → cannot evaluate this axis; record not-enforced for fixture.
          pav[cost]="not-enforced"
        else
          pav[cost]=$("$harness_dir/evaluate-direction.sh" \
            --axis cost --direction "$direction" --tolerance-pct "$tolerance_pct" \
            --baseline "$b_cost" --candidate "$c_cost")
        fi
        ;;
    esac
  done

  # Build verdict string. Collect regressed axes in declaration order.
  declare -a regressed=()
  if [[ ${pav[accuracy]} == "regression" ]]; then regressed+=(accuracy); fi
  for (( i=0; i < n_axes; i++ )); do
    local m
    m=$(printf '%s' "$declared_json" | jq -r ".[$i].metric")
    [[ $m == "accuracy" || $m == "output_quality" ]] && continue
    if [[ ${pav[$m]} == "regression" ]]; then regressed+=("$m"); fi
  done

  local verdict
  if (( ${#regressed[@]} == 0 )); then
    verdict="pass"
  else
    local joined
    joined=$(IFS=" + "; echo "${regressed[*]}")
    verdict="regression ($joined)"
  fi

  jq -nc \
    --arg acc "${pav[accuracy]}" \
    --arg tok "${pav[tokens]}" \
    --arg tim "${pav[time]}" \
    --arg cst "${pav[cost]}" \
    --arg v "$verdict" \
    '{per_axis_verdicts:{accuracy:$acc, tokens:$tok, time:$tim, cost:$cst}, verdict:$v}'
}

for fixture_dir in "${fixtures[@]}"; do
  slug=${fixture_dir##*/}

  baseline_json=$(run_arm "$fixture_dir" "$baseline_dir" "baseline")
  candidate_json=$(run_arm "$fixture_dir" "$candidate_dir" "candidate")

  b_pass=$(printf '%s' "$baseline_json" | jq -r '.assertion_pass')
  c_pass=$(printf '%s' "$candidate_json" | jq -r '.assertion_pass')
  b_tok=$(printf '%s' "$baseline_json" | jq -r '.tokens.total')
  c_tok=$(printf '%s' "$candidate_json" | jq -r '.tokens.total')
  b_time=$(printf '%s' "$baseline_json" | jq -r '.time_seconds')
  c_time=$(printf '%s' "$candidate_json" | jq -r '.time_seconds')
  b_cost=$(printf '%s' "$baseline_json" | jq -r '.cost_usd')
  c_cost=$(printf '%s' "$candidate_json" | jq -r '.cost_usd')
  b_inconc=$(printf '%s' "$baseline_json" | jq -r '.inconclusive_reason // ""')
  c_inconc=$(printf '%s' "$candidate_json" | jq -r '.inconclusive_reason // ""')

  if [[ $gate_mode == "foundation_strict" ]]; then
    verdict=$(compute_verdict_strict "$b_pass" "$c_pass" "$b_tok" "$c_tok" "$b_inconc" "$c_inconc")
    per_axis_verdicts_json='{"accuracy":"not-enforced","tokens":"not-enforced"}'
  else
    pa_envelope=$(compute_verdict_per_axis "$b_pass" "$c_pass" "$b_tok" "$c_tok" \
      "$b_inconc" "$c_inconc" "$b_time" "$c_time" "$b_cost" "$c_cost" "$slug")
    verdict=$(printf '%s' "$pa_envelope" | jq -r '.verdict')
    per_axis_verdicts_json=$(printf '%s' "$pa_envelope" | jq -c '.per_axis_verdicts')
  fi

  delta=$(( c_tok - b_tok ))
  delta_time=$(awk -v a="$b_time" -v b="$c_time" 'BEGIN { printf "%.4f", b - a }')
  if [[ $b_cost == "null" || $c_cost == "null" ]]; then
    delta_cost=null
  else
    delta_cost=$(awk -v a="$b_cost" -v b="$c_cost" 'BEGIN { printf "%.4f", b - a }')
  fi

  case $verdict in
    pass) ;;
    inconclusive*) any_inconclusive=1 ;;
    *) any_regression=1 ;;
  esac

  jq -cn \
    --arg slug "$slug" \
    --arg fp "$fixture_dir" \
    --argjson b "$baseline_json" \
    --argjson c "$candidate_json" \
    --argjson dt "$delta" \
    --argjson dts "$delta_time" \
    --argjson dcs "$delta_cost" \
    --arg verdict "$verdict" \
    --argjson pav "$per_axis_verdicts_json" \
    '{fixture_slug:$slug, fixture_path:$fp, baseline:$b, candidate:$c, delta_tokens:$dt, delta_time_seconds:$dts, delta_cost_usd:$dcs, verdict:$verdict, per_axis_verdicts:$pav}' \
    >> "$ndjson_results"

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

# --- AE: Cost-axis-all-null edge case (FR-AE-012 / Edge case) ----------------
if [[ $gate_mode == "per_axis_direction" ]]; then
  # Check if cost is declared.
  cost_declared=0
  for m in "${declared_metrics[@]}"; do
    [[ $m == "cost" ]] && cost_declared=1
  done
  if (( cost_declared == 1 )); then
    any_nonnull_cost=0
    while IFS= read -r line; do
      bc=$(printf '%s' "$line" | jq -r '.baseline.cost_usd')
      cc=$(printf '%s' "$line" | jq -r '.candidate.cost_usd')
      if [[ $bc != "null" || $cc != "null" ]]; then any_nonnull_cost=1; break; fi
    done <"$ndjson_results"
    if (( any_nonnull_cost == 0 )); then
      bail_out "cost axis declared but no fixture produced a cost_usd value (all model IDs missing from pricing.json)"
    fi
  fi
fi

# --- AE: excluded-fraction-high warning (FR-AE-007) -------------------------
if (( n_all > 0 )) && (( n_excluded > 0 )); then
  pct_x100=$(( n_excluded * 1000 / n_all ))    # tenths of percent → 30.0% = 300
  if (( pct_x100 > 300 )); then
    pct_int=$(( pct_x100 / 10 ))
    printf 'excluded-fraction-high: %d/%d (%d%%) exceeds 30%% threshold\n' "$n_excluded" "$n_all" "$pct_int" >>"$warnings_file"
  fi
fi

t_end=$(date +%s)
completed_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
wall_clock=$((t_end - t_start))

# --- Render report ----------------------------------------------------------
# Build aggregate-warnings string from warnings file (deduplicate, preserve order).
aggregate_warnings=$(awk '!seen[$0]++' "$warnings_file" | paste -sd $'\n' -)

# Build excluded-fixtures table TSV for renderer (one row per fixture).
excluded_tsv=$(mktemp)
trap 'rm -f "$ndjson_results" "$warnings_file" "$excluded_tsv"' EXIT
: >"$excluded_tsv"
for ((i=0; i<n_excluded; i++)); do
  printf '%s\t%s\n' "${excluded_slugs[$i]}" "${excluded_reasons[$i]}" >>"$excluded_tsv"
done

# Build declared-axes summary string.
if [[ $gate_mode == "per_axis_direction" ]]; then
  declared_axes_str=$(printf '%s' "$prd_empirical_quality" | jq -r '[.[] | "\(.metric) (\(.direction))"] | join(", ")')
  if [[ -z $declared_axes_str ]]; then declared_axes_str="(none — strict gate)"; fi
else
  declared_axes_str="(none — strict gate)"
fi

if [[ $gate_mode == "per_axis_direction" ]]; then
  rigor_str="min_fixtures=$min_fixtures, tolerance_pct=$tolerance_pct"
  blast_str=$prd_blast_radius
else
  rigor_str="(n/a — strict gate)"
  blast_str="(n/a — strict gate)"
fi

prd_str=${prd_path:-"(none — foundation strict-gate fallback)"}

RESEARCH_REPORT_RUN_UUID="$run_uuid" \
RESEARCH_REPORT_BASELINE_PLUGIN_DIR="$baseline_dir" \
RESEARCH_REPORT_CANDIDATE_PLUGIN_DIR="$candidate_dir" \
RESEARCH_REPORT_CORPUS_DIR="$corpus_dir" \
RESEARCH_REPORT_STARTED="$started_iso" \
RESEARCH_REPORT_COMPLETED="$completed_iso" \
RESEARCH_REPORT_WALL_CLOCK="${wall_clock}s" \
RESEARCH_REPORT_PRD="$prd_str" \
RESEARCH_REPORT_GATE_MODE="$gate_mode" \
RESEARCH_REPORT_BLAST_RADIUS="$blast_str" \
RESEARCH_REPORT_RIGOR_ROW="$rigor_str" \
RESEARCH_REPORT_DECLARED_AXES="$declared_axes_str" \
RESEARCH_REPORT_EXCLUDED_COUNT="$n_excluded" \
RESEARCH_REPORT_EXCLUDED_TSV="$excluded_tsv" \
RESEARCH_REPORT_WARNINGS="$aggregate_warnings" \
  bash "$harness_dir/render-research-report.sh" "$report_path" < "$ndjson_results"

# --- Aggregate verdict ------------------------------------------------------
if (( any_regression > 0 )); then overall="FAIL"
elif (( any_inconclusive > 0 )); then overall="FAIL"
else overall="PASS"
fi

printf '# Aggregate verdict: %s (gate_mode=%s)\n' "$overall" "$gate_mode"
printf '# Report: %s\n' "$report_path"

if (( any_regression > 0 )); then exit 1; fi
if (( any_inconclusive > 0 )); then exit 2; fi
exit 0
