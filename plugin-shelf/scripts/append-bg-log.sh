#!/usr/bin/env bash
# append-bg-log.sh — append one line to the per-day background sub-agent log
#
# Usage:
#   append-bg-log.sh <counter_before> <counter_after> <threshold> <action> [notes]
#
# Writes to $BG_LOG_DIR/report-issue-bg-<YYYY-MM-DD>.md (default .kiln/logs/).
# Creates the directory and file on first write of the day.
# Format (FR-009):
#
#   <ISO-8601 UTC timestamp> | counter_before=<N> | counter_after=<N> | threshold=<N> | action=<a> | notes=<string>
#
# Exit: always 0 (log failures must not crash the bg sub-agent).

set -u

BG_LOG_DIR="${BG_LOG_DIR:-.kiln/logs}"

main() {
  local before="${1:-0}" after="${2:-0}" threshold="${3:-10}" action="${4:-unknown}" notes="${5:-}"
  local day ts logfile line

  day=$(date -u +%Y-%m-%d 2>/dev/null || echo "unknown-date")
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown-timestamp")
  logfile="${BG_LOG_DIR}/report-issue-bg-${day}.md"

  # Best-effort mkdir + append. Swallow all errors.
  mkdir -p "$BG_LOG_DIR" 2>/dev/null || true

  # Note: printf '\n' terminator is necessary so each invocation appends a
  # distinct line (grep/wc -l count correctly). Without it, 11 successive
  # appends produce a single physical line with 11 concatenated entries.
  line=$(printf '%s | counter_before=%s | counter_after=%s | threshold=%s | action=%s | notes=%s' \
           "$ts" "$before" "$after" "$threshold" "$action" "$notes")

  {
    printf '%s\n' "$line"
  } >> "$logfile" 2>/dev/null || true

  # Echo the line so callers can confirm (harmless if nobody reads stdout).
  printf '%s\n' "$line"
  return 0
}

main "$@"
