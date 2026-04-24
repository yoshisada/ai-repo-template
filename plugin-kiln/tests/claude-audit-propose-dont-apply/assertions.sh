#!/usr/bin/env bash
# Assertions for claude-audit-propose-dont-apply (T032).
# Validates FR-016: audit NEVER edits CLAUDE.md. Acceptance: User Story 3 Scenario 4.
set -euo pipefail

CANARY="FIXTURE_CANARY_DO_NOT_EDIT"

if [[ ! -f CLAUDE.md ]]; then
  echo "FAIL: CLAUDE.md was deleted (FR-016 violation — skill must never edit)" >&2
  exit 1
fi

if ! grep -qF "$CANARY" CLAUDE.md; then
  echo "FAIL: canary line '$CANARY' missing from CLAUDE.md — skill modified the file" >&2
  cat CLAUDE.md >&2
  exit 1
fi

# Also confirm a preview WAS written — the skill's actual output channel.
shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
if [[ ${#previews[@]} -eq 0 ]]; then
  echo "FAIL: no preview log produced — skill should emit findings to .kiln/logs/" >&2
  exit 1
fi

echo "PASS: canary preserved in CLAUDE.md; preview log written to .kiln/logs/" >&2
exit 0
