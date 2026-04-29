#!/usr/bin/env bash
# FR-007/FR-008 (wheel-user-input): Happy-path harness assertions.
#
# This test runs in the kiln:test harness subprocess which does NOT fire
# PostToolUse/Stop hooks. As a result:
#   - activate.sh does NOT create a state file (no hook interception)
#   - wheel-flag-needs-input returns "no active workflow" (no state file)
#   - The workflow does NOT archive (no hooks to advance cursor)
#
# What IS verifiable in this environment:
#   1. The step instruction was followed — output file exists.
#   2. The wheel binary was invoked (not Python's wheel) — checked by
#      ensuring no "invalid choice" error appears in logs.
#   3. wheel-flag-needs-input was attempted — wheel.log shows the call
#      (even if it failed with no-active-workflow).
#
# The FR-007/FR-008 invariants (flag-set, flag-clear, cursor-advance) require
# a full wheel hook environment and are verified by wheel-test / manual
# testing, not by this harness test.
set -euo pipefail

shopt -s nullglob

# 1. Output file present
if [[ ! -s .wheel/outputs/ask.json ]]; then
  echo "FAIL: .wheel/outputs/ask.json is missing or empty" >&2
  ls -la .wheel/outputs/ 2>/dev/null || echo "(no .wheel/outputs/)" >&2
  exit 1
fi
echo "PASS: output file written" >&2

# 2. Verify correct wheel binary was invoked (not Python's wheel).
#    If Python wheel intercepted, wheel.log would show "invalid choice"
#    instead of the expected wheel-flag-needs-input entry.
if [[ -f .wheel/logs/wheel.log ]]; then
  if grep -q 'invalid choice' .wheel/logs/wheel.log 2>/dev/null; then
    echo "FAIL: Python wheel was intercepted (PATH issue not fixed)" >&2
    exit 1
  fi
  echo "PASS: no Python-wheel interception detected"

  # 3. Verify wheel-flag-needs-input was called (log entry exists).
  #    Even if it returned "no-active-workflow", the call proves the
  #    PATH fix allowed the plugin script to be found.
  if grep -q 'flag-needs-input' .wheel/logs/wheel.log 2>/dev/null; then
    echo "PASS: wheel-flag-needs-input was invoked (PATH resolution worked)" >&2
  else
    echo "FAIL: wheel-flag-needs-input was not logged" >&2
    exit 1
  fi
else
  echo "WARN: .wheel/logs/wheel.log not found — PATH resolution unverifiable" >&2
fi

echo "PASS: happy-path fixture assertions satisfied" >&2
exit 0
