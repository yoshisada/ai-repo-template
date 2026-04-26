#!/usr/bin/env bash
# lint-classifier-output-quality-warning.sh — assert that the verbatim FR-016
# warning string appears in classifier output JSON when `output_quality` is
# in proposed_axes.
#
# Spec:     specs/research-first-completion/spec.md (FR-016, SC-011)
# Contract: specs/research-first-completion/contracts/interfaces.md §10
#
# Usage:
#   lint-classifier-output-quality-warning.sh <classifier-output-json>
#
# Exit:  0 PASS (no output_quality, OR output_quality + warning verbatim);
#        2 FAIL with `Bail out! lint-classifier-output-quality-warning:
#                     missing verbatim warning` on stderr.

set -u

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  printf 'Bail out! lint-classifier-output-quality-warning: missing input argument\n' >&2
  exit 2
fi

# Verbatim FR-016 warning (single literal, character-for-character):
WARNING='(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)'

# 1. If research_inference is absent → exit 0 (nothing to lint).
HAS_INF=$(printf '%s' "$INPUT" | jq -r 'has("research_inference")' 2>/dev/null)
if [ "$HAS_INF" != "true" ]; then
  exit 0
fi

# 2. If proposed_axes does NOT contain output_quality → exit 0.
HAS_OQ=$(printf '%s' "$INPUT" | jq -r '.research_inference.proposed_axes // [] | any(.metric == "output_quality")' 2>/dev/null)
if [ "$HAS_OQ" != "true" ]; then
  exit 0
fi

# 3. Rationale MUST contain the verbatim FR-016 warning.
RATIONALE=$(printf '%s' "$INPUT" | jq -r '.research_inference.rationale // ""' 2>/dev/null)
if printf '%s' "$RATIONALE" | grep -qF -- "$WARNING"; then
  exit 0
fi

printf 'Bail out! lint-classifier-output-quality-warning: missing verbatim warning\n' >&2
exit 2
