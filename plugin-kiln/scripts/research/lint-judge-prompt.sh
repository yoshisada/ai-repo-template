#!/usr/bin/env bash
# lint-judge-prompt.sh — assert plugin-kiln/agents/output-quality-judge.md
# (or its _src/ source) contains the literal `{{rubric_verbatim}}` interpolation
# token exactly once AND no rubric-summarization regex patterns.
#
# Satisfies: FR-011, SC-003.
# Contract:  specs/research-first-plan-time-agents/contracts/interfaces.md §9.1.
#
# Usage:
#   plugin-kiln/scripts/research/lint-judge-prompt.sh
#
# Exit:
#   0 — PASS (token present exactly once + no summarization language)
#   2 — FAIL with `Bail out! lint-judge-prompt: <reason>` on stderr

set -euo pipefail
LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

bail() {
  printf 'Bail out! lint-judge-prompt: %s\n' "$1" >&2
  exit 2
}

# Lint BOTH the compiled output AND the source if it exists.
TARGETS=()
COMPILED="$REPO_ROOT/plugin-kiln/agents/output-quality-judge.md"
SRC="$REPO_ROOT/plugin-kiln/agents/_src/output-quality-judge.md"
[[ -f "$COMPILED" ]] && TARGETS+=("$COMPILED")
[[ -f "$SRC" ]] && TARGETS+=("$SRC")

[[ ${#TARGETS[@]} -gt 0 ]] || bail "no judge agent file found at $COMPILED or $SRC"

for target in "${TARGETS[@]}"; do
  # Assert {{rubric_verbatim}} appears exactly once.
  count=$(grep -c -F '{{rubric_verbatim}}' "$target" || true)
  if [[ "$count" -ne 1 ]]; then
    bail "expected exactly 1 occurrence of {{rubric_verbatim}} in ${target#$REPO_ROOT/}; found $count"
  fi

  # Assert no rubric-summarization regex patterns (case-insensitive).
  # Patterns from contracts §9.1.
  PATTERNS=(
    'summari[sz]e the rubric'
    'paraphrase the rubric'
    'condense the rubric'
    'key points of the rubric'
    'gist of the rubric'
  )
  for pat in "${PATTERNS[@]}"; do
    if grep -q -i -E "$pat" "$target"; then
      bail "rubric-summarization language found in ${target#$REPO_ROOT/}: pattern \"$pat\" matched"
    fi
  done
done

exit 0
