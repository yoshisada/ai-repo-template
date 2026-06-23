#!/usr/bin/env bash
# compute-cost-usd.sh — Derive cost_usd for a single fixture-arm using
# token counts and a hand-maintained pricing table.
#
# Satisfies: FR-AE-011 (cost formula),
#            FR-AE-012 (null + warning on model-miss).
# Contract:  specs/research-first-axis-enrichment/contracts/interfaces.md §5.
#
# Synopsis:
#   compute-cost-usd.sh --pricing-json <path> --model-id <id> \
#                       --input-tokens <int> --output-tokens <int> \
#                       --cached-input-tokens <int>
#
# Stdout (success):  <cost_usd-4dp>   (e.g., 0.0001)
# Stdout (model-miss): null           (stderr emits `pricing-table-miss: <id>`)
# Stdout (empty/missing model): null  (stderr emits `pricing-table-miss: <empty>`)
# Stderr: warnings (model-miss) + diagnostics.
# Exit:   0 success (including model-miss case);
#         2 pricing.json malformed or missing.
#
# Formula:
#   cost_usd = (in × $/in + out × $/out + cached × $/cached) / 1_000_000
# Result rounded to 4 decimal places via printf "%.4f".
#
# Determinism: same inputs → byte-identical stdout (NFR-AE-002).
set -euo pipefail
LC_ALL=C
export LC_ALL

bail() {
  printf 'Bail out! %s\n' "$1" >&2
  exit 2
}

pricing= model= it= ot= ct=
while (( $# > 0 )); do
  case $1 in
    --pricing-json) pricing=${2:-}; shift 2 ;;
    --model-id) model=${2-}; shift 2 ;;
    --input-tokens) it=${2:-}; shift 2 ;;
    --output-tokens) ot=${2:-}; shift 2 ;;
    --cached-input-tokens) ct=${2:-}; shift 2 ;;
    *) bail "unknown flag: $1" ;;
  esac
done

[[ -n $pricing ]] || bail "missing --pricing-json"
[[ -n ${it+x} ]] || bail "missing --input-tokens"
[[ -n ${ot+x} ]] || bail "missing --output-tokens"
[[ -n ${ct+x} ]] || bail "missing --cached-input-tokens"

[[ -f $pricing ]] || bail "pricing.json not found: $pricing"
if ! jq_err=$(jq -e . "$pricing" 2>&1 >/dev/null); then
  bail "pricing.json malformed: $jq_err"
fi

[[ $it =~ ^[0-9]+$ ]] || bail "input-tokens must be non-negative int: $it"
[[ $ot =~ ^[0-9]+$ ]] || bail "output-tokens must be non-negative int: $ot"
[[ $ct =~ ^[0-9]+$ ]] || bail "cached-input-tokens must be non-negative int: $ct"

# Empty/missing model_id → null + warning.
if [[ -z $model ]]; then
  printf 'pricing-table-miss: <empty>\n' >&2
  printf 'null\n'
  exit 0
fi

# Look up model in pricing table.
entry=$(jq -c --arg m "$model" '.[$m] // empty' "$pricing")
if [[ -z $entry ]]; then
  printf 'pricing-table-miss: %s\n' "$model" >&2
  printf 'null\n'
  exit 0
fi

read -r in_rate out_rate cached_rate <<<"$(printf '%s' "$entry" | jq -r '[.input_per_mtok, .output_per_mtok, .cached_input_per_mtok] | @tsv')"

# Compute via awk for cross-platform float math.
cost=$(awk -v it="$it" -v ot="$ot" -v ct="$ct" \
            -v ir="$in_rate" -v or="$out_rate" -v cr="$cached_rate" \
            'BEGIN { printf "%.4f", (it*ir + ot*or + ct*cr) / 1000000.0 }')

printf '%s\n' "$cost"
