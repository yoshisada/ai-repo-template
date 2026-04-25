#!/usr/bin/env bash
# SC-8 fixture — CLAUDE.md documents the 6 architectural rules from FR-A-12 plus
# Theme B directive syntax (FR-B-8) plus composer integration recipe (R-3).
# Greps for canonical phrases reviewers can match against.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"

[[ ! -f "$CLAUDE_MD" ]] && { echo "FAIL: CLAUDE.md not found at $CLAUDE_MD" >&2; exit 1; }

fail=0
declare -i pass_count=0

assert_grep() {
  local label="$1"; shift
  if grep -qF -- "$1" "$CLAUDE_MD"; then
    pass_count+=1
  else
    echo "FAIL: CLAUDE.md missing canonical phrase ($label): '$1'" >&2
    fail=1
  fi
}

# FR-A-12 rule (a)
assert_grep "FR-A-12 (a) — no general-purpose for specialized roles" "NEVER use \`general-purpose\` for specialized roles"
# FR-A-12 rule (b)
assert_grep "FR-A-12 (b) — one role per subagent_type" "One role per registered subagent_type"
# FR-A-12 rule (c)
assert_grep "FR-A-12 (c) — injection is prompt-layer" "Injection is prompt-layer"
# FR-A-12 rule (d)
assert_grep "FR-A-12 (d) — top-level orchestration" "Top-level orchestration is correct"
# FR-A-12 rule (e)
assert_grep "FR-A-12 (e) — agent registration session-bound" "Agent registration is session-bound"
# FR-A-12 rule (f)
assert_grep "FR-A-12 (f) — plain text invisible, relay via SendMessage" "Plain-text output is invisible to team-lead"
assert_grep "FR-A-12 (f) — relay via SendMessage canonical phrase" "always relay via SendMessage"

# FR-B-8 — directive syntax
assert_grep "FR-B-8 — directive marker" "<!-- @include"
assert_grep "FR-B-8 — _shared dir convention" "_shared/coordination-protocol.md"

# Composer integration recipe (R-3)
assert_grep "Recipe — compose-context.sh script ref" "compose-context.sh"
assert_grep "Recipe — composer is opt-in" "composer NEVER calls"

# Plugin-prefixed subagent_type guidance
assert_grep "subagent_type plugin-prefixed canonical phrase" "kiln:research-runner"

if [[ $fail -ne 0 ]]; then
  echo "FAIL: claude-md-architectural-rules — $pass_count phrases matched, but at least one missing" >&2
  exit 1
fi

echo "PASS: claude-md-architectural-rules — all $pass_count canonical phrases present in CLAUDE.md"
