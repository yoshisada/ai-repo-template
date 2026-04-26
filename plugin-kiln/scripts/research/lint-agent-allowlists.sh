#!/usr/bin/env bash
# lint-agent-allowlists.sh — assert the literal `tools:` allowlist strings in
# both fixture-synthesizer and output-quality-judge agents have not drifted from
# the committed values per CLAUDE.md NFR-005.
#
# Satisfies: NFR-005.
# Contract:  specs/research-first-plan-time-agents/contracts/interfaces.md §9.3.
#
# Usage:
#   plugin-kiln/scripts/research/lint-agent-allowlists.sh
#
# Exit:
#   0 — PASS (both files match expected allowlist strings)
#   2 — FAIL with `Bail out! lint-agent-allowlists: <agent> drift — expected: "<expected>"  actual: "<actual>"`

set -euo pipefail
LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

bail() {
  printf 'Bail out! lint-agent-allowlists: %s\n' "$1" >&2
  exit 2
}

# Expected (canonical) allowlist strings — character-equal modulo whitespace
# around commas. Implemented by extracting the `tools:` line from frontmatter,
# normalising commas/whitespace, and comparing.

normalize_tools_line() {
  # stdin: a single `tools: ...` line
  # stdout: comma-separated, single-space-after-each-comma, no trailing/leading ws
  sed -E 's/^tools:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^$' \
    | paste -sd ',' - \
    | sed 's/,/, /g'
}

check_agent() {
  local agent_path="$1"
  local expected="$2"

  if [[ ! -f "$agent_path" ]]; then
    bail "agent file not found: ${agent_path#$REPO_ROOT/}"
  fi

  # Extract the first `tools:` line within the frontmatter (between leading ---
  # and the next ---).
  local tools_line
  tools_line=$(awk '
    BEGIN{in_fm=0; done=0}
    /^---[[:space:]]*$/ { if(!in_fm){in_fm=1; next} else {exit} }
    in_fm && /^tools:/ && !done { print; done=1 }
  ' "$agent_path")

  if [[ -z "$tools_line" ]]; then
    bail "${agent_path#$REPO_ROOT/} drift — expected: \"tools: $expected\"  actual: \"<no tools: line in frontmatter>\""
  fi

  local actual
  actual=$(printf '%s\n' "$tools_line" | normalize_tools_line)

  if [[ "$actual" != "$expected" ]]; then
    bail "${agent_path#$REPO_ROOT/} drift — expected: \"$expected\"  actual: \"$actual\""
  fi
}

check_agent "$REPO_ROOT/plugin-kiln/agents/fixture-synthesizer.md" "Read, Write, SendMessage, TaskUpdate"
check_agent "$REPO_ROOT/plugin-kiln/agents/output-quality-judge.md" "Read, SendMessage, TaskUpdate"

exit 0
