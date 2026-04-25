#!/usr/bin/env bash
# render-research-report.sh — Emit the research markdown report.
#
# Foundation: FR-S-004, NFR-S-005, plan §Decision 2, contracts §4 + §8.
# Axis-enrichment: FR-AE-015, FR-AE-016, contracts §9 — adds Time + Cost
# columns, Per-Axis Verdict column, extended aggregate header (PRD,
# Gate mode, Blast radius, Rigor row, Declared axes, Excluded fixtures),
# optional Excluded Fixtures + Warnings subsections.
#
# Usage:
#   render-research-report.sh <report-path> < <ndjson-stdin>
#
# Stdin: NDJSON stream — one per-fixture-result JSON object per line.
#        Shape per axis-enrichment contracts §1 (extends foundation §1).
# Stdout: empty.
# Stderr: diagnostics on parse / write failure.
# Exit:   0 report written; 2 stdin parse error or write failure.
#
# Determinism (SC-S-006 / SC-AE-005): byte-identical NDJSON input →
# byte-identical markdown output, modulo §3 exclusion comparator
# (timestamps + UUIDs + scratch paths).
set -euo pipefail
LC_ALL=C
export LC_ALL

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
# Axis-enrichment fields:
: "${RESEARCH_REPORT_PRD:=(none — foundation strict-gate fallback)}"
: "${RESEARCH_REPORT_GATE_MODE:=foundation_strict}"
: "${RESEARCH_REPORT_BLAST_RADIUS:=(n/a — strict gate)}"
: "${RESEARCH_REPORT_RIGOR_ROW:=(n/a — strict gate)}"
: "${RESEARCH_REPORT_DECLARED_AXES:=(none — strict gate)}"
: "${RESEARCH_REPORT_EXCLUDED_COUNT:=0}"
: "${RESEARCH_REPORT_EXCLUDED_TSV:=}"
: "${RESEARCH_REPORT_WARNINGS:=}"

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
for entry in "${fixtures[@]}"; do
  v=$(printf '%s' "$entry" | jq -r '.verdict')
  case $v in
    pass) ;;
    regression*) regressions=$((regressions + 1)) ;;
    inconclusive*) inconclusives=$((inconclusives + 1)) ;;
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
  echo "**PRD**: ${RESEARCH_REPORT_PRD}"
  echo "**Gate mode**: ${RESEARCH_REPORT_GATE_MODE}"
  echo "**Blast radius**: ${RESEARCH_REPORT_BLAST_RADIUS}"
  echo "**Rigor row**: ${RESEARCH_REPORT_RIGOR_ROW}"
  echo "**Declared axes**: ${RESEARCH_REPORT_DECLARED_AXES}"
  echo "**Started**: ${RESEARCH_REPORT_STARTED}"
  echo "**Completed**: ${RESEARCH_REPORT_COMPLETED}"
  echo "**Wall-clock**: ${RESEARCH_REPORT_WALL_CLOCK}"
  echo
  echo "## Per-Fixture Results"
  echo
  echo "| Fixture | Acc B/C | Tokens B/C | Δ Tok | Time B/C | Δ Time | Cost B/C | Δ Cost | Per-Axis Verdict |"
  echo "|---|---|---|---|---|---|---|---|---|"
  for entry in "${fixtures[@]}"; do
    printf '%s\n' "$entry" | jq -r '
      def acc(arm): if arm.assertion_pass then "pass" else "fail" end;
      def fmt_num(v): if v == null then "—" else (v|tostring) end;
      def fmt_cost(c): if c == null then "—" else "$\(c|tostring)" end;
      def fmt_delta_cost(d): if d == null then "—" else (if d >= 0 then "+$\(d|tostring)" else "-$\((-d)|tostring)" end) end;
      def axis_line:
        # Foundation back-compat: if no per_axis_verdicts present (or empty), fall
        # back to the bare verdict string. SC-AE-005 anchor — keeps foundation
        # regression-detect test (which feeds synthetic NDJSON without per_axis_verdicts)
        # passing post-PRD.
        ((.per_axis_verdicts // {}) as $pav |
         [
           ($pav.accuracy // null | if . then "accuracy:\(.)" else null end),
           ($pav.tokens   // null | if . then "tokens:\(.)"   else null end),
           ($pav.time     // null | if . then "time:\(.)"     else null end),
           ($pav.cost     // null | if . then "cost:\(.)"     else null end)
         ] | map(select(. != null and (. | endswith(":not-enforced") | not)))) as $pa_list
        | (if ($pa_list | length) > 0 then ($pa_list | join(", "))
           else (.verdict // "—") end);
      def time_cell:
        if (.baseline.time_seconds // null) == null and (.candidate.time_seconds // null) == null then "—/—"
        else "\(fmt_num(.baseline.time_seconds))/\(fmt_num(.candidate.time_seconds))" end;
      def time_delta:
        if (.delta_time_seconds // null) == null then "—" else (.delta_time_seconds|tostring) end;
      "| \(.fixture_slug) | \(acc(.baseline))/\(acc(.candidate)) | \(.baseline.tokens.total)/\(.candidate.tokens.total) | \(.delta_tokens) | \(time_cell) | \(time_delta) | \(fmt_cost(.baseline.cost_usd))/\(fmt_cost(.candidate.cost_usd)) | \(fmt_delta_cost(.delta_cost_usd)) | \(axis_line) |"
    '
  done
  echo
  echo "## Aggregate"
  echo
  echo "- **Total fixtures**: ${n}"
  echo "- **Excluded fixtures**: ${RESEARCH_REPORT_EXCLUDED_COUNT}"
  echo "- **Regressions**: ${regressions}"
  echo "- **Overall**: ${overall}"
  echo "- **Report UUID**: ${RESEARCH_REPORT_RUN_UUID}"
  echo "- **Runtime**: ${RESEARCH_REPORT_WALL_CLOCK}"

  # Excluded Fixtures section — only present when excluded_fixtures: declared.
  if [[ -n $RESEARCH_REPORT_EXCLUDED_TSV && -s $RESEARCH_REPORT_EXCLUDED_TSV ]]; then
    echo
    echo "## Excluded Fixtures"
    echo
    echo "| Fixture | Reason |"
    echo "|---|---|"
    while IFS=$'\t' read -r ex_slug ex_reason; do
      [[ -n $ex_slug ]] || continue
      printf '| %s | %s |\n' "$ex_slug" "$ex_reason"
    done <"$RESEARCH_REPORT_EXCLUDED_TSV"
  fi

  # Warnings section — only present when at least one warning was emitted.
  if [[ -n $RESEARCH_REPORT_WARNINGS ]]; then
    echo
    echo "## Warnings"
    echo
    while IFS= read -r w; do
      [[ -z $w ]] && continue
      echo "- $w"
    done <<<"$RESEARCH_REPORT_WARNINGS"
  fi

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
