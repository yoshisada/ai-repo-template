#!/usr/bin/env bash
# FR-013/US5/SC-004 (wheel-user-input): WHEEL_NONINTERACTIVE=1 blocks
# wheel-flag-needs-input even on allow_user_input: true steps. The agent
# should have seen the exit 1 and proceeded to write the output.
set -euo pipefail

shopt -s nullglob

# 1. Output file exists.
if [[ ! -s .wheel/outputs/headless.json ]]; then
  echo "FAIL: output file missing or empty — agent didn't complete the step" >&2
  exit 1
fi
echo "PASS: agent wrote output after non-interactive denial" >&2

# 2. No state file recorded awaiting_user_input=true (the CLI must have
# rejected before mutating state).
state_files=( .wheel/state_*.json .wheel/history/state_*.json )
for sf in "${state_files[@]}"; do
  [[ -f "$sf" ]] || continue
  a=$(jq -r '.steps[0].awaiting_user_input // false' "$sf" 2>/dev/null)
  if [[ "$a" == "true" ]]; then
    echo "FAIL: $sf shows awaiting_user_input=true — WHEEL_NONINTERACTIVE=1 should have blocked" >&2
    exit 1
  fi
done
echo "PASS: WHEEL_NONINTERACTIVE=1 blocked the flag set (SC-004)" >&2

exit 0
