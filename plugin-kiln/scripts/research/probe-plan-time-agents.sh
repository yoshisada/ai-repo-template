#!/usr/bin/env bash
# probe-plan-time-agents.sh — emit `synthesizer|judge|both|skip` based on
# whether a PRD declares fixture_corpus: synthesized AND/OR an
# empirical_quality[].metric: output_quality axis.
#
# Used by:
#   - /plan SKILL.md Phase 1.5 (single skip-or-spawn decision probe).
#   - plugin-kiln/tests/plan-time-agents-skip-perf/run.sh (NFR-006b).
#
# Performance contract (NFR-006a + NFR-006b):
#   When the parsed PRD frontmatter JSON is already available (axis-enrichment
#   has run), prefer the JSON projection — sub-millisecond. Otherwise fall
#   back to a SINGLE `grep -E` (~5 ms per research.md §baseline). This script
#   MUST NOT spawn a fresh python3/jq cold-fork solely for the probe.
#
# Usage:
#   probe-plan-time-agents.sh --prd <abs-prd-path> [--frontmatter-json <abs-path-or-stdin->]
#
# Stdout: one of `synthesizer | judge | both | skip`.
# Exit:   0 on success, 2 on missing PRD path.

set -euo pipefail
LC_ALL=C
export LC_ALL

bail() { printf 'Bail out! %s\n' "$1" >&2; exit 2; }

prd= fm_json=
while (( $# > 0 )); do
  case $1 in
    --prd) prd=${2:-}; shift 2 ;;
    --frontmatter-json) fm_json=${2:-}; shift 2 ;;
    *) bail "probe-plan-time-agents: unknown flag: $1" ;;
  esac
done

[[ -n $prd && -f $prd ]] || bail "probe-plan-time-agents: --prd missing or not a file: $prd"

has_synth=0
has_oq=0

# Path A (preferred): use already-parsed JSON projection. Sub-millisecond.
if [[ -n "$fm_json" ]]; then
  json_text=
  if [[ "$fm_json" == "-" ]]; then
    json_text=$(cat)
  elif [[ -f "$fm_json" ]]; then
    json_text=$(cat "$fm_json")
  fi
  if [[ -n "$json_text" ]]; then
    # The `fixture_corpus` field is not currently in parse-prd-frontmatter.sh's
    # projection; check the raw frontmatter for it via grep below. The
    # output_quality probe is JSON-projected.
    if printf '%s' "$json_text" | grep -q '"metric":"output_quality"'; then
      has_oq=1
    fi
  fi
fi

# Path B: single grep -E pass against the raw PRD. ~5 ms per research.md §baseline.
# This catches `fixture_corpus: synthesized` (not in JSON projection yet) and
# is a backup for output_quality detection when fm_json is absent/empty.
if grep -q -E '^fixture_corpus:[[:space:]]*synthesized([[:space:]]|$)' "$prd"; then
  has_synth=1
fi
if [[ "$has_oq" == "0" ]]; then
  if grep -q -E '(^|[[:space:]{,])metric:[[:space:]]*output_quality([[:space:]},]|$)' "$prd"; then
    has_oq=1
  fi
fi

if [[ "$has_synth" == "1" && "$has_oq" == "1" ]]; then
  printf 'both\n'
elif [[ "$has_synth" == "1" ]]; then
  printf 'synthesizer\n'
elif [[ "$has_oq" == "1" ]]; then
  printf 'judge\n'
else
  printf 'skip\n'
fi
