#!/usr/bin/env bash
# extract-signal-g.sh — Signal (g): install works cleanly.
#
# Vision signal (g): a fresh consumer runs the scaffold and is productive
# without fighting setup.
#
# Heuristic (V1, deterministic): count smoke / kiln-test verdict reports under
# `.kiln/logs/kiln-test-*.md` over the last 30 days. Their presence evidences
# install/runtime smoke runs were exercised; their text often carries pass/fail.
# We report the count as a coarse "smoke activity" indicator. A deeper pass-rate
# computation would parse the verdicts — left as a V2 refinement (NFR-002).
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(g)"
TARGET=">=1 kiln-test verdict in last 30d"

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

COUNT=0
while IFS= read -r -d '' f; do
  COUNT=$((COUNT + 1))
done < <(find "$LOGS_DIR" -maxdepth 1 -name 'kiln-test-*.md' -mtime -30 -print0 2>/dev/null || true)

if (( COUNT >= 1 )); then
  STATUS="on-track"
else
  STATUS="at-risk"
fi

EVIDENCE=".kiln/logs/kiln-test-*.md count, last 30d"
printf '%s\t%s\t%s\t%s\t%s\n' "$SIGNAL_ID" "$COUNT" "$TARGET" "$STATUS" "$EVIDENCE"
