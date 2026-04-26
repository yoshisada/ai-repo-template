#!/usr/bin/env bash
# lint-synthesizer-prompt.sh — assert plugin-kiln/agents/fixture-synthesizer.md
# (or its _src/ source) contains the verbatim diversity-prompt string per FR-008.
#
# Satisfies: FR-008.
# Contract:  specs/research-first-plan-time-agents/contracts/interfaces.md §9.2.
#
# Usage:
#   plugin-kiln/scripts/research/lint-synthesizer-prompt.sh
#
# Exit:
#   0 — PASS (verbatim string present)
#   2 — FAIL with `Bail out! lint-synthesizer-prompt: <reason>` on stderr

set -euo pipefail
LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

bail() {
  printf 'Bail out! lint-synthesizer-prompt: %s\n' "$1" >&2
  exit 2
}

DIVERSITY_PROMPT='generate fixtures that exercise edge cases: empty inputs, maximum-size inputs, typical inputs, adversarial inputs'

TARGETS=()
COMPILED="$REPO_ROOT/plugin-kiln/agents/fixture-synthesizer.md"
SRC="$REPO_ROOT/plugin-kiln/agents/_src/fixture-synthesizer.md"
[[ -f "$COMPILED" ]] && TARGETS+=("$COMPILED")
[[ -f "$SRC" ]] && TARGETS+=("$SRC")

[[ ${#TARGETS[@]} -gt 0 ]] || bail "no synthesizer agent file found at $COMPILED or $SRC"

for target in "${TARGETS[@]}"; do
  if ! grep -q -F "$DIVERSITY_PROMPT" "$target"; then
    bail "missing diversity-prompt verbatim string in ${target#$REPO_ROOT/}"
  fi
done

exit 0
