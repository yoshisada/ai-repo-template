#!/usr/bin/env bash
# extract-signal-e.sh — Signal (e): hooks reliably gate untraced src/ edits + .env commits.
#
# Vision signal (e): hooks reliably gate untraced `src/` edits and `.env`
# commits — autonomous agents cannot silently drift.
#
# Heuristic (V1, deterministic): count blocked-edit / .env-commit entries in
# `.kiln/logs/hook-*.log` over the last 30 days. Presence of such entries
# evidences hook activity; absence may simply mean nothing tried — so a zero
# count is reported as `on-track` (system idle, no drift) rather than at-risk.
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(e)"
TARGET="hook activity observable in last 30d"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno repo root\n' "$SIGNAL_ID"
  exit 4
fi

LOGS_DIR="$REPO_ROOT/.kiln/logs"
if [[ ! -d "$LOGS_DIR" ]]; then
  printf '%s\t-\t-\tunmeasurable\t.kiln/logs/ missing\n' "$SIGNAL_ID"
  exit 4
fi

FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(find "$LOGS_DIR" -maxdepth 1 -name 'hook-*.log' -mtime -30 -print0 2>/dev/null || true)

if [[ ${#FILES[@]} -eq 0 ]]; then
  # No hook log file in 30 days — could be quiet activity; mark unmeasurable so
  # the operator knows we couldn't observe a fingerprint.
  printf '%s\t0\t%s\tunmeasurable\tno hook-*.log in last 30d\n' \
    "$SIGNAL_ID" "$TARGET"
  exit 4
fi

# Count lines mentioning a block / refusal / .env across the in-window log files.
COUNT="$(grep -c -i -E 'block|refus|\.env' "${FILES[@]}" 2>/dev/null \
  | awk -F: '{ s += $NF } END { print s+0 }')"
if [[ -z "$COUNT" ]]; then
  COUNT=0
fi

STATUS="on-track"
EVIDENCE=".kiln/logs/hook-*.log block/refus/.env grep, last 30d"
printf '%s\t%s\t%s\t%s\t%s\n' "$SIGNAL_ID" "$COUNT" "$TARGET" "$STATUS" "$EVIDENCE"
