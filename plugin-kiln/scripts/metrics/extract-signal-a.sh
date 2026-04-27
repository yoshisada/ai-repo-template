#!/usr/bin/env bash
# extract-signal-a.sh — Signal (a): idea-captured-via-clay → reviewed-PR-via-build-prd.
#
# Vision signal (a): An idea captured via /clay:clay-idea reaches a reviewed PR via
# /kiln:kiln-build-prd with zero-to-few human interventions.
#
# Heuristic (V1, deterministic): count merge commits over the last 90 days whose
# subject line carries the `build-prd` marker. The presence of build-prd-stamped
# merges is a coarse but cheap proxy for "ideas reaching reviewed PRs".
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".
#
# Stdout (success, exit 0):
#   <signal-id>\t<current-value>\t<target>\t<on-track|at-risk>\t<evidence>
# Stdout (unmeasurable, exit 4):
#   <signal-id>\t-\t-\tunmeasurable\t<reason>

set -euo pipefail

SIGNAL_ID="(a)"
TARGET=">=1 build-prd merge in 90d"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/.git" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno git repo at %s\n' "$SIGNAL_ID" "${REPO_ROOT:-?}"
  exit 4
fi

cd "$REPO_ROOT"

# Count merge commits in the last 90 days whose subject mentions build-prd.
# `git log --merges --since=90.days` is read-only. Subject grep is case-insensitive.
COUNT="$(git log --merges --since=90.days.ago --pretty=%s 2>/dev/null \
  | grep -c -i 'build-prd' || true)"

if [[ -z "$COUNT" ]]; then
  COUNT=0
fi

if (( COUNT >= 1 )); then
  STATUS="on-track"
else
  STATUS="at-risk"
fi

EVIDENCE="git log --merges --since=90.days (build-prd in subject)"
printf '%s\t%s\t%s\t%s\t%s\n' "$SIGNAL_ID" "$COUNT" "$TARGET" "$STATUS" "$EVIDENCE"
