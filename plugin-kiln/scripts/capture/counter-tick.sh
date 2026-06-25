#!/usr/bin/env bash
# counter-tick.sh — increment the shared shelf full-sync counter from a capture surface.
#
# WHY: the `.shelf-config` full-sync counter gates how often a full Obsidian
# reconciliation runs. Historically only /kiln:kiln-report-issue incremented it, so the
# cadence ignored the other three capture surfaces (feedback, roadmap, mistake). Per the
# rearchitecture, ALL FOUR capture surfaces tick the same shared counter so full-sync
# cadence reflects total capture volume, not just issues.
#
# This is a thin, surface-agnostic wrapper around plugin-shelf's shelf-counter.sh:
# locate it cross-plugin, run increment-and-decide, append a source-tagged cadence log
# line, and print the decision JSON so the caller can fire /shelf:shelf-sync on rollover.
#
# Usage: counter-tick.sh <source>          (<source> = feedback | roadmap | mistake | report-issue)
# Prints shelf-counter's JSON: {"before":N,"after":N,"threshold":N,"action":"increment|full-sync"}
# Exit 0 even when shelf is unreachable (capture must never fail because sync is down).

set -u

SOURCE="${1:-unknown}"

# Locate plugin-shelf/scripts. Probe order mirrors kiln-pi-apply's resilient resolution:
# wheel-exported plugin dir → this script's sibling plugin → install cache.
_find_shelf_scripts() {
  local c
  # Explicit, version-correct probes first: the wheel-exported plugin dir, the sibling
  # plugin under a --plugin-dir/cache install, and the source-repo layout.
  for c in \
    "${WORKFLOW_PLUGIN_DIR:-}/../plugin-shelf/scripts" \
    "${CLAUDE_PLUGIN_ROOT:-}/../plugin-shelf/scripts" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../plugin-shelf/scripts" 2>/dev/null && pwd)"; do
    [ -n "$c" ] && [ -f "$c/shelf-counter.sh" ] && { printf '%s\n' "$c"; return 0; }
  done
  # Cache fallback: multiple installed shelf versions can match. Take the NEWEST by
  # version (sort -V descending), not the arbitrary glob order, to avoid resolving a
  # stale counter implementation.
  for c in $(ls -d "$HOME/.claude/plugins/cache"/*/shelf/*/scripts 2>/dev/null | sort -t/ -k7 -V -r); do
    [ -f "$c/shelf-counter.sh" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

SHELF_SCRIPTS="$(_find_shelf_scripts || true)"
if [ -z "$SHELF_SCRIPTS" ]; then
  echo '{"action":"skip","note":"shelf-counter.sh not found — capture recorded, counter not ticked"}'
  exit 0
fi

DECISION="$(bash "$SHELF_SCRIPTS/shelf-counter.sh" increment-and-decide 2>/dev/null)" || {
  echo '{"action":"skip","note":"shelf-counter increment failed — capture recorded"}'
  exit 0
}

# Source-tagged cadence log (separate from report-issue's bg log, so the SC-007 canary on
# report-issue-bg-*.md is untouched). Best-effort.
BG_LOG_DIR="${BG_LOG_DIR:-.kiln/logs}"
if command -v jq >/dev/null 2>&1; then
  BEFORE="$(printf '%s' "$DECISION" | jq -r '.before // "?"' 2>/dev/null)"
  AFTER="$(printf '%s' "$DECISION" | jq -r '.after // "?"' 2>/dev/null)"
  THRESHOLD="$(printf '%s' "$DECISION" | jq -r '.threshold // "?"' 2>/dev/null)"
  ACTION="$(printf '%s' "$DECISION" | jq -r '.action // "?"' 2>/dev/null)"
  mkdir -p "$BG_LOG_DIR" 2>/dev/null || true
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  DAY="$(date -u +%Y-%m-%d 2>/dev/null || echo unknown)"
  printf '%s | source=%s | counter_before=%s | counter_after=%s | threshold=%s | action=%s\n' \
    "$TS" "$SOURCE" "$BEFORE" "$AFTER" "$THRESHOLD" "$ACTION" \
    >> "${BG_LOG_DIR}/capture-counter-${DAY}.md" 2>/dev/null || true
fi

printf '%s\n' "$DECISION"
