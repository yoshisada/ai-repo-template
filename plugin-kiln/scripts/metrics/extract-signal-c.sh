#!/usr/bin/env bash
# extract-signal-c.sh — Signal (c): capture surfaces close their loops.
#
# Vision signal (c): items captured in one session become PRDs via
# /kiln:kiln-distill and shipped features in a later session.
#
# Heuristic (V1, deterministic): count PRDs under docs/features/*/PRD.md whose
# YAML frontmatter (or in-body metadata) cites a `derived_from:` block. Each such
# PRD is direct evidence that a capture surface closed at least one loop.
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(c)"
TARGET=">=1 PRD with derived_from:"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno repo root\n' "$SIGNAL_ID"
  exit 4
fi

FEATURES_DIR="$REPO_ROOT/docs/features"
if [[ ! -d "$FEATURES_DIR" ]]; then
  printf '%s\t-\t-\tunmeasurable\tdocs/features/ missing\n' "$SIGNAL_ID"
  exit 4
fi

COUNT=0
while IFS= read -r -d '' prd; do
  if grep -q -E '^derived_from:' "$prd" 2>/dev/null; then
    COUNT=$((COUNT + 1))
  fi
done < <(find "$FEATURES_DIR" -maxdepth 3 -name 'PRD.md' -print0 2>/dev/null || true)

if (( COUNT >= 1 )); then
  STATUS="on-track"
else
  STATUS="at-risk"
fi

EVIDENCE="docs/features/*/PRD.md 'derived_from:' grep"
printf '%s\t%s\t%s\t%s\t%s\n' "$SIGNAL_ID" "$COUNT" "$TARGET" "$STATUS" "$EVIDENCE"
