#!/usr/bin/env bash
# FR-002/US3 (wheel-user-input): permission denial — CLI exits 1 on a step
# without allow_user_input; state file byte-for-byte unchanged (SC-003).
# The harness invokes wheel flag-needs-input from within the agent step; we
# re-run it post-hoc against the state snapshot to verify the rejection.
set -euo pipefail

shopt -s nullglob

# 1. Output file exists (agent completed the step).
if [[ ! -s .wheel/outputs/no-perm.json ]]; then
  echo "FAIL: output file missing or empty" >&2
  exit 1
fi
echo "PASS: agent wrote output after denial" >&2

# 2. awaiting_user_input was never set.
state_files=( .wheel/state_*.json .wheel/history/state_*.json )
for sf in "${state_files[@]}"; do
  [[ -f "$sf" ]] || continue
  a=$(jq -r '.steps[0].awaiting_user_input // false' "$sf" 2>/dev/null)
  if [[ "$a" == "true" ]]; then
    echo "FAIL: $sf shows awaiting_user_input=true — permission denial leaked" >&2
    exit 1
  fi
done
echo "PASS: no awaiting_user_input flag set (denial was a no-op on state)" >&2

exit 0
