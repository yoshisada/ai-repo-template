#!/usr/bin/env bash
# Assertions for claude-audit-cache-stale (T030).
# Validates FR-015 + Clarification #3: cache fetched >30 days old → staleness flag.
set -euo pipefail

shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
if [[ ${#previews[@]} -eq 0 ]]; then
  echo "FAIL: no preview log produced" >&2
  exit 1
fi
preview=$(ls -1t "${previews[@]}" | head -1)

# Must flag staleness. Accept any of these canonical phrasings:
#   "cache stale" / "cache is stale" / "stale cache" / "stale (fetched ..."
if ! grep -qiE '(cache.+stale|stale.+cache|>[[:space:]]*30[[:space:]]*days)' "$preview"; then
  echo "FAIL: preview does not flag cache staleness (FR-015)" >&2
  cat "$preview" >&2
  exit 1
fi

echo "PASS: stale-cache fixture produced a staleness flag in preview" >&2
exit 0
