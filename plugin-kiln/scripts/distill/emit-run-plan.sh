#!/usr/bin/env bash
# emit-run-plan.sh — format the run-plan block printed at the end of
# multi-theme distill output.
#
# FR-018 of spec `coach-driven-capture-ergonomics`: when N>=2 PRDs are emitted,
# the skill MUST print a run-plan block summarizing the emitted PRDs and
# suggesting `/kiln:kiln-build-prd <slug>` invocations in an explicit order
# with a one-line rationale per line. When N<2, this script MUST emit zero
# bytes (FR-018 requires run-plan OMISSION on single-PRD runs).
#
# Per contracts/interfaces.md §Module: plugin-kiln/scripts/distill/ →
# emit-run-plan.sh — input JSON schema and output format are frozen.
#
# Determinism: no timestamps, no $RANDOM. Output ordered by documented
# severity rules (foundational → highest → med → low → null), with input
# order preserved within same severity.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: emit-run-plan.sh <emissions-json>

  <emissions-json> — path to a JSON file describing emitted PRDs:
    [
      { "slug": "<slug>",
        "path": "docs/features/<date>-<slug>/PRD.md",
        "severity_hint": "foundational|highest|med|low|null",
        "rationale": "<optional one-liner>" }
    ]

Exit codes:
  0 — success.
  2 — usage error.
EOF
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

INPUT="$1"

if [[ ! -f "$INPUT" ]]; then
  echo "error: emissions JSON not found: $INPUT" >&2
  exit 2
fi

# FR-018: omit the block entirely when N<2.
COUNT=$(jq 'length' "$INPUT")
if [[ "$COUNT" -lt 2 ]]; then
  # Zero bytes on stdout. Explicit early-exit keeps the contract crisp.
  exit 0
fi

# FR-018 severity ordering: foundational → highest → med → low → null.
# Within same severity, preserve INPUT ORDER (NOT alphabetical). We map each
# severity label to a numeric rank, then stable-sort.
#
# jq's `sort_by` is documented as stable (array-position preserved on ties),
# so this gives us the "within same severity, preserve input order" rule
# for free.
SORTED=$(jq -c '
  map(. + {
    _rank: (
      if   .severity_hint == "foundational" then 0
      elif .severity_hint == "highest"      then 1
      elif .severity_hint == "med"          then 2
      elif .severity_hint == "low"          then 3
      else 4
      end
    )
  })
  | sort_by(._rank)
' "$INPUT")

# Render the markdown block.
echo "## Run Plan"
echo
echo "Suggested pipeline order for the emitted PRDs:"
echo

# Numbered list — one PRD per line with rationale.
i=1
while IFS= read -r row; do
  SLUG=$(echo "$row" | jq -r '.slug')
  SEV=$(echo "$row" | jq -r '.severity_hint // "null"')
  RATIONALE=$(echo "$row" | jq -r '.rationale // ""')

  # If no rationale provided, derive one from severity_hint.
  if [[ -z "$RATIONALE" || "$RATIONALE" == "null" ]]; then
    case "$SEV" in
      foundational) RATIONALE="foundational — touches shared infrastructure" ;;
      highest)      RATIONALE="highest severity from bundle" ;;
      med)          RATIONALE="medium severity" ;;
      low)          RATIONALE="low severity" ;;
      *)            RATIONALE="no severity hint; deterministic input order" ;;
    esac
  fi

  echo "${i}. \`/kiln:kiln-build-prd ${SLUG}\` — ${RATIONALE}"
  i=$((i + 1))
done < <(echo "$SORTED" | jq -c '.[]')
