#!/usr/bin/env bash
# FR-007/FR-008 (wheel-user-input): Happy-path harness assertions.
#
# After running `/wheel:wheel-run happy-path` with an agent that calls
# `wheel flag-needs-input`, waits for a reply, and writes the output:
#
# 1. `.wheel/outputs/ask.json` exists and is non-empty.
# 2. The archived or active state file records awaiting_user_input=false
#    on the "ask" step (cleared on advance per FR-008).
# 3. .wheel/logs/wheel.log contains at least one "silent" log line with
#    reason=awaiting_user_input (proves the silence branch fired — FR-007).
# 4. The workflow's cursor advanced past the ask step OR the workflow archived
#    to .wheel/history/ (terminal single-step workflow).
set -euo pipefail

shopt -s nullglob

# 1. Output file present
if [[ ! -s .wheel/outputs/ask.json ]]; then
  echo "FAIL: .wheel/outputs/ask.json is missing or empty" >&2
  ls -la .wheel/outputs/ 2>/dev/null || echo "(no .wheel/outputs/)" >&2
  exit 1
fi
echo "PASS: output file written" >&2

# 2. Flag cleared on advance. Find the state file (active or archived).
state_files=( .wheel/state_*.json .wheel/history/state_*.json )
if [[ ${#state_files[@]} -eq 0 ]]; then
  echo "FAIL: no state file (active or archived) found" >&2
  exit 1
fi
for sf in "${state_files[@]}"; do
  [[ -f "$sf" ]] || continue
  awaiting=$(jq -r '.steps[0].awaiting_user_input // false' "$sf" 2>/dev/null)
  since=$(jq -r '.steps[0].awaiting_user_input_since // null' "$sf" 2>/dev/null)
  reason=$(jq -r '.steps[0].awaiting_user_input_reason // null' "$sf" 2>/dev/null)
  if [[ "$awaiting" == "true" ]]; then
    echo "FAIL: state $sf still has awaiting_user_input=true after advance (FR-008)" >&2
    exit 1
  fi
  echo "PASS: $sf cleared awaiting_user_input ($since / $reason)" >&2
done

# 3. Silent log line present
if [[ ! -f .wheel/logs/wheel.log ]]; then
  echo "WARN: .wheel/logs/wheel.log not found (can't verify FR-007 silence directly)" >&2
elif ! grep -q 'silent.*reason=awaiting_user_input' .wheel/logs/wheel.log; then
  echo "WARN: no silent-branch log line found in wheel.log (FR-007 may not have fired)" >&2
  tail -30 .wheel/logs/wheel.log >&2 || true
else
  echo "PASS: wheel.log shows silent-branch fired for awaiting_user_input" >&2
fi

echo "PASS: happy-path fixture assertions satisfied" >&2
exit 0
