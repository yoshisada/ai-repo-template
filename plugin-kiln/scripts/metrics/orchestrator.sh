#!/usr/bin/env bash
# orchestrator.sh — Theme D win-condition scorecard orchestrator.
#
# Walks the eight per-signal extractors, normalizes their output through
# render-row.sh, and writes the report to BOTH stdout AND a timestamped log
# under .kiln/logs/metrics-<UTC-timestamp>.md.
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — orchestrator.sh".
# FRs: FR-015 (skill walks repo state, 8-row scorecard), FR-017 (graceful
# degrade — extractor failure → unmeasurable, exit 0), FR-019 (timestamped log
# without overwrite).
#
# Inputs from environment:
#   KILN_REPO_ROOT       optional — defaults to git rev-parse --show-toplevel.
#   KILN_METRICS_NOW     optional — overrides timestamp for test determinism.
#
# Exit code: 0 always. FR-017 graceful degrade — never propagate extractor errors.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER_ROW="$SCRIPT_DIR/render-row.sh"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOGS_DIR="$REPO_ROOT/.kiln/logs"
mkdir -p "$LOGS_DIR"

# FR-019 timestamp determinism. Honour KILN_METRICS_NOW for fixtures.
if [[ -n "${KILN_METRICS_NOW:-}" ]]; then
  TIMESTAMP="$KILN_METRICS_NOW"
else
  TIMESTAMP="$(date -u +%Y-%m-%d-%H%M%S)"
fi

# FR-019: never overwrite an existing log; suffix -<N> on collision.
LOG_PATH="$LOGS_DIR/metrics-$TIMESTAMP.md"
if [[ -e "$LOG_PATH" ]]; then
  N=2
  while [[ -e "$LOGS_DIR/metrics-$TIMESTAMP-$N.md" ]]; do
    N=$((N + 1))
  done
  LOG_PATH="$LOGS_DIR/metrics-$TIMESTAMP-$N.md"
fi

# Buffer the report so stdout and the log file are byte-identical (SC-007).
REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT

{
  printf '# Vision Scorecard — %s\n\n' "$TIMESTAMP"
  printf 'Mappings are extractor-derived; targets are V1 heuristics — see plugin-kiln/scripts/metrics/extract-signal-<x>.sh for the per-signal sources.\n\n'
  printf '| signal | current_value | target | status | evidence |\n'
  printf '|---|---|---|---|---|\n'
} > "$REPORT"

# FR-018 / SC-007: 8 rows in (a)..(h) order.
SIGNALS=(a b c d e f g h)
for s in "${SIGNALS[@]}"; do
  EXTRACTOR="$SCRIPT_DIR/extract-signal-$s.sh"
  SIGNAL_ID="($s)"

  if [[ ! -x "$EXTRACTOR" && ! -f "$EXTRACTOR" ]]; then
    # Extractor missing entirely (covers spec.md edge case).
    "$RENDER_ROW" "$SIGNAL_ID" "-" "-" "unmeasurable" "extractor missing" >> "$REPORT"
    continue
  fi

  # Capture stdout + exit code; extractor failure is converted to unmeasurable
  # (FR-017) — orchestrator never propagates non-zero.
  OUT="$(bash "$EXTRACTOR" 2>/dev/null)" || true
  RC=$?

  # Defensive — `set -uo pipefail` without `-e` keeps RC available.
  if [[ -z "$OUT" ]]; then
    "$RENDER_ROW" "$SIGNAL_ID" "-" "-" "unmeasurable" "extractor emitted nothing" >> "$REPORT"
    continue
  fi

  # Take only the first line — extractors are contracted to emit exactly one.
  FIRST_LINE="$(printf '%s\n' "$OUT" | head -n 1)"

  # Parse tab-separated fields.
  IFS=$'\t' read -r SID CUR TGT STAT EVID <<< "$FIRST_LINE"

  # Normalise — if any required field is empty, treat the row as unmeasurable.
  if [[ -z "${SID:-}" || -z "${STAT:-}" ]]; then
    "$RENDER_ROW" "$SIGNAL_ID" "-" "-" "unmeasurable" "extractor output malformed" >> "$REPORT"
    continue
  fi

  # render-row enforces the status enum; if the extractor returned an unknown
  # status, downgrade to unmeasurable rather than abort the whole report.
  case "$STAT" in
    on-track|at-risk|unmeasurable)
      "$RENDER_ROW" "$SID" "${CUR:--}" "${TGT:--}" "$STAT" "${EVID:--}" >> "$REPORT"
      ;;
    *)
      "$RENDER_ROW" "$SIGNAL_ID" "-" "-" "unmeasurable" "extractor returned unknown status: $STAT" >> "$REPORT"
      ;;
  esac
done

# Persist log first (FR-019 audit trail), then echo to stdout (SC-007 user surface).
cp "$REPORT" "$LOG_PATH"
cat "$REPORT"

# FR-017 graceful degrade — orchestrator always succeeds.
exit 0
