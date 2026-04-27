#!/usr/bin/env bash
# extract-signal-b.sh — Signal (b): high-signal escalations, not friction.
#
# Vision signal (b): When the system interrupts, it's because precedent is
# genuinely absent — not because a gate was wired to always ask.
#
# Heuristic (V1, deterministic): count `escalation` events in
# `.wheel/history/*.jsonl` over the last 90 days. We can't judge "high-signal"
# automatically — the count itself is a coarse health indicator. A target of
# `<=10/90d` is the prescribed signal-shape per FR-016. Operators may revisit.
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(b)"
TARGET="<=10 escalations in 90d"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno repo root\n' "$SIGNAL_ID"
  exit 4
fi

HIST_DIR="$REPO_ROOT/.wheel/history"
if [[ ! -d "$HIST_DIR" ]]; then
  printf '%s\t-\t-\tunmeasurable\t.wheel/history/ missing\n' "$SIGNAL_ID"
  exit 4
fi

# Find jsonl files modified in last 90 days. -mtime -90 = within last 90 days.
FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(find "$HIST_DIR" -maxdepth 1 -name '*.jsonl' -mtime -90 -print0 2>/dev/null || true)

if [[ ${#FILES[@]} -eq 0 ]]; then
  printf '%s\t0\t%s\ton-track\tno escalation events in last 90d (.wheel/history)\n' \
    "$SIGNAL_ID" "$TARGET"
  exit 0
fi

# Count occurrences of `"escalation"` token across the files. Cheap deterministic
# substring grep — operators looking for verifiability run the same grep by hand.
COUNT="$(grep -ch 'escalation' "${FILES[@]}" 2>/dev/null | awk '{ s += $1 } END { print s+0 }')"
if [[ -z "$COUNT" ]]; then
  COUNT=0
fi

if (( COUNT <= 10 )); then
  STATUS="on-track"
else
  STATUS="at-risk"
fi

EVIDENCE=".wheel/history/*.jsonl 'escalation' grep, last 90d"
printf '%s\t%s\t%s\t%s\t%s\n' "$SIGNAL_ID" "$COUNT" "$TARGET" "$STATUS" "$EVIDENCE"
