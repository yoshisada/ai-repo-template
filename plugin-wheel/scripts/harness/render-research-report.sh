#!/usr/bin/env bash
# render-research-report.sh — Emit the research markdown report.
#
# Satisfies: FR-S-004 (report shape), NFR-S-005 (readability), plan §Decision 2.
# Contract:  specs/research-first-foundation/contracts/interfaces.md §4 + §8.
#
# Usage:
#   render-research-report.sh <report-path> < <ndjson-stdin>
#
# Args:
#   <report-path>   absolute path for the output markdown report.
#                   Caller (research-runner.sh) owns generating the UUID.
#
# Stdin: NDJSON stream — one per-fixture-result JSON object per line.
#        Shape per contracts §1. EOF terminates input.
#
# Stdout: empty.
# Stderr: diagnostics on parse / write failure.
#
# Exit:
#   0 — report written.
#   2 — stdin parse error OR write failure.
#
# Determinism (SC-S-006): byte-identical NDJSON input → byte-identical
# markdown output, modulo the §8 timestamp-modulo-list (Started, Completed,
# Wall-clock, Run UUID, Report UUID — all caller-supplied and substituted in
# via env vars).
set -euo pipefail

if (( $# != 1 )); then
  echo "render-research-report.sh: expected 1 arg (report path), got $#" >&2
  exit 2
fi

report_path=$1

# Caller-supplied environmental fields (all OPTIONAL — defaulted to "n/a" if
# unset, so the renderer is testable in isolation):
: "${RESEARCH_REPORT_RUN_UUID:=n/a}"
: "${RESEARCH_REPORT_BASELINE_PLUGIN_DIR:=n/a}"
: "${RESEARCH_REPORT_CANDIDATE_PLUGIN_DIR:=n/a}"
: "${RESEARCH_REPORT_CORPUS_DIR:=n/a}"
: "${RESEARCH_REPORT_STARTED:=n/a}"
: "${RESEARCH_REPORT_COMPLETED:=n/a}"
: "${RESEARCH_REPORT_WALL_CLOCK:=n/a}"

# Read all NDJSON stdin lines into an array (skip blank lines).
declare -a fixtures=()
while IFS= read -r line || [[ -n $line ]]; do
  [[ -z $line ]] && continue
  fixtures+=("$line")
done

n=${#fixtures[@]}

# Validate JSON shape eagerly — fail loud per NFR-S-008 sibling discipline.
for entry in "${fixtures[@]}"; do
  if ! printf '%s' "$entry" | jq -e . >/dev/null 2>&1; then
    echo "render-research-report.sh: malformed NDJSON input line: $entry" >&2
    exit 2
  fi
done

# Compute aggregate counts.
regressions=0
inconclusives=0
declare -a regression_slugs=()
for entry in "${fixtures[@]}"; do
  v=$(printf '%s' "$entry" | jq -r '.verdict')
  case $v in
    pass) ;;
    regression*) regressions=$((regressions + 1)); regression_slugs+=("$(printf '%s' "$entry" | jq -r '.fixture_slug')") ;;
    inconclusive*) inconclusives=$((inconclusives + 1)); regression_slugs+=("$(printf '%s' "$entry" | jq -r '.fixture_slug')") ;;
  esac
done

if (( regressions > 0 || inconclusives > 0 )); then
  overall="FAIL"
else
  overall="PASS"
fi

# -- Write report -------------------------------------------------------------
{
  echo "# Research Run Report"
  echo
  echo "**Run UUID**: ${RESEARCH_REPORT_RUN_UUID}"
  echo "**Baseline plugin-dir**: ${RESEARCH_REPORT_BASELINE_PLUGIN_DIR}"
  echo "**Candidate plugin-dir**: ${RESEARCH_REPORT_CANDIDATE_PLUGIN_DIR}"
  echo "**Corpus**: ${RESEARCH_REPORT_CORPUS_DIR}"
  echo "**Started**: ${RESEARCH_REPORT_STARTED}"
  echo "**Completed**: ${RESEARCH_REPORT_COMPLETED}"
  echo "**Wall-clock**: ${RESEARCH_REPORT_WALL_CLOCK}"
  echo
  echo "## Per-Fixture Results"
  echo
  echo "| Fixture | Baseline Acc | Candidate Acc | Baseline Tokens | Candidate Tokens | Δ Tokens | Verdict |"
  echo "|---|---|---|---|---|---|---|"
  for entry in "${fixtures[@]}"; do
    printf '%s\n' "$entry" | jq -r '
      def acc(arm): if arm.assertion_pass then "pass" else "fail" end;
      "| \(.fixture_slug) | \(acc(.baseline)) | \(acc(.candidate)) | \(.baseline.tokens.total) | \(.candidate.tokens.total) | \(.delta_tokens) | \(.verdict) |"
    '
  done
  echo
  echo "## Aggregate"
  echo
  echo "- **Total fixtures**: ${n}"
  echo "- **Regressions**: ${regressions}"
  echo "- **Overall**: ${overall}"
  echo "- **Report UUID**: ${RESEARCH_REPORT_RUN_UUID}"
  echo "- **Runtime**: ${RESEARCH_REPORT_WALL_CLOCK}"

  # Diagnostics block — only on FAIL (per §8).
  if [[ $overall == "FAIL" ]]; then
    echo
    echo "## Diagnostics"
    echo
    for entry in "${fixtures[@]}"; do
      v=$(printf '%s' "$entry" | jq -r '.verdict')
      case $v in
        regression*|inconclusive*) ;;
        *) continue ;;
      esac
      printf '%s\n' "$entry" | jq -r '
        "- **\(.fixture_slug)** — verdict `\(.verdict)`",
        "  - Baseline transcript: `\(.baseline.transcript_path)`",
        "  - Candidate transcript: `\(.candidate.transcript_path)`",
        "  - Baseline scratch (retained on fail): `\(.baseline.scratch_dir)`",
        "  - Candidate scratch (retained on fail): `\(.candidate.scratch_dir)`"
      '
    done
  fi
} > "$report_path"
