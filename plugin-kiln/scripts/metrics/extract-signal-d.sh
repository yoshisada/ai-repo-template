#!/usr/bin/env bash
# extract-signal-d.sh — Signal (d): self-improvement loop closes.
#
# Vision signal (d): AI mistakes captured in one session become proposed
# manifest/template edits in a later session, and those edits land.
#
# Heuristic (V1): count files under .kiln/mistakes/ as the local capture
# population. The "landed" leg lives in Obsidian's @inbox/closed/ and is read
# via shelf MCP — that path is not file-system-traversable from a deterministic
# shell extractor. We emit the captured count and tag the row `unmeasurable`
# when the closed-inbox half cannot be observed locally.
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(d)"
TARGET=">=1 mistake closed via @inbox/closed/"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno repo root\n' "$SIGNAL_ID"
  exit 4
fi

MISTAKES_DIR="$REPO_ROOT/.kiln/mistakes"
if [[ ! -d "$MISTAKES_DIR" ]]; then
  printf '%s\t-\t-\tunmeasurable\t.kiln/mistakes/ missing (capture leg unavailable)\n' "$SIGNAL_ID"
  exit 4
fi

CAPTURED=0
while IFS= read -r -d '' f; do
  CAPTURED=$((CAPTURED + 1))
done < <(find "$MISTAKES_DIR" -maxdepth 2 -name '*.md' -print0 2>/dev/null || true)

# The Obsidian @inbox/closed/ count is the "landed" leg. Without an MCP read in
# this shell, we cannot observe it deterministically — emit unmeasurable with
# the captured count surfaced as context for the operator.
printf '%s\t%s captured\t%s\tunmeasurable\t@inbox/closed/ not readable from shell (Obsidian MCP)\n' \
  "$SIGNAL_ID" "$CAPTURED" "$TARGET"
exit 4
