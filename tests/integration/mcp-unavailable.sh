#!/usr/bin/env bash
# tests/integration/mcp-unavailable.sh
# Acceptance Scenario US6#1 (FR-015): when the Obsidian MCP is unavailable,
# the write-proposal-mcp agent step MUST:
#   1. Emit exactly one warning line to its output file.
#   2. Create no partial file in @inbox/open/.
#   3. Not retry indefinitely.
#   4. Exit 0 (from the wheel's perspective).
#
# The agent's behavior is encoded in the instruction text, so this test
# verifies that the instruction documents the required behavior verbatim.
# A live MCP-unavailable integration test requires a wheel runtime with
# toggleable tool availability, which is out of scope for the bash harness.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORKFLOW="$ROOT/plugin-shelf/workflows/propose-manifest-improvement.json"
EXPECTED_WARN="warn: obsidian MCP unavailable; manifest improvement proposal not persisted"

fail=0

if [ ! -f "$WORKFLOW" ]; then
  printf 'FAIL workflow-exists — %s\n' "$WORKFLOW"; exit 1
fi

instruction=$(jq -r '.steps[] | select(.id=="write-proposal-mcp") | .instruction' "$WORKFLOW")
if [ -z "$instruction" ]; then
  printf 'FAIL mcp-agent-instruction-exists\n'; exit 1
fi

# FR-015: the exact warn line MUST appear in the instruction.
if printf '%s' "$instruction" | grep -qF "$EXPECTED_WARN"; then
  printf 'PASS warn-line-literal\n'
else
  printf 'FAIL warn-line-literal — expected: %s\n' "$EXPECTED_WARN"; fail=1
fi

# FR-015: "exit 0" behavior MUST be explicit (agent step succeeds from wheel's view).
if printf '%s' "$instruction" | grep -qiE 'end the step successfully|exits? 0|caller workflow continues'; then
  printf 'PASS exit-0-documented\n'
else
  printf 'FAIL exit-0-documented\n'; fail=1
fi

# FR-015: no retry beyond the bounded collision loop.
if printf '%s' "$instruction" | grep -qiE 'do not retry|NOT retry|MUST NOT retry'; then
  printf 'PASS no-retry-documented\n'
else
  printf 'FAIL no-retry-documented\n'; fail=1
fi

# FR-015: no partial file — must be explicit.
if printf '%s' "$instruction" | grep -qiE 'partial file|NOT create any partial'; then
  printf 'PASS no-partial-file-documented\n'
else
  printf 'FAIL no-partial-file-documented\n'; fail=1
fi

# FR-019: collision handling -2..-9 suffixes must be documented (related to
# the MCP-unavailable fall-through path — if all 9 collide, treat as MCP
# unavailable per R-009).
if printf '%s' "$instruction" | grep -qE '\-2|\-3.*\-9'; then
  printf 'PASS collision-retry-documented\n'
else
  printf 'FAIL collision-retry-documented\n'; fail=1
fi

[ "$fail" -eq 0 ]
