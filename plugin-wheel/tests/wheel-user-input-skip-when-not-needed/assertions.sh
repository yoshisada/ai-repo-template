#!/usr/bin/env bash
# FR-001/FR-002/US2 (wheel-user-input): Assert the agent did NOT pause even
# though allow_user_input: true. Verifies that runtime decision is real —
# SC-002.
set -euo pipefail

shopt -s nullglob

# 1. Output file exists.
if [[ ! -s .wheel/outputs/auto.json ]]; then
  echo "FAIL: output file missing or empty" >&2
  exit 1
fi
echo "PASS: agent wrote output" >&2

# 2. awaiting_user_input never set: current + archived state all show false
# (or field absent).
state_files=( .wheel/state_*.json .wheel/history/state_*.json )
any_awaiting=false
for sf in "${state_files[@]}"; do
  [[ -f "$sf" ]] || continue
  a=$(jq -r '.steps[0].awaiting_user_input // false' "$sf" 2>/dev/null)
  if [[ "$a" == "true" ]]; then
    any_awaiting=true
    echo "FAIL: $sf has awaiting_user_input=true (SC-002 violation)" >&2
  fi
done
if [[ "$any_awaiting" == "false" ]]; then
  echo "PASS: no state file ever had awaiting_user_input=true (SC-002)" >&2
else
  exit 1
fi

# 3. No silent-branch log line (nothing triggered the silence branch).
if [[ -f .wheel/logs/wheel.log ]] && grep -q 'silent.*reason=awaiting_user_input' .wheel/logs/wheel.log; then
  echo "FAIL: wheel.log shows silent branch fired — agent paused when it shouldn't have" >&2
  exit 1
fi
echo "PASS: no silent-branch log entries (no pause observed)" >&2

exit 0
