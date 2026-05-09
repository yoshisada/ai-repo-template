#!/usr/bin/env bash
# Assertions for third-party-model-skip-demo. Only runs if the demo
# require-env gates passed (i.e. the caller manually set the
# WHEEL_TEST_THIRD_PARTY_DEMO_* vars to point at a real provider).
# In standard CI / dev runs the fixture is SKIPPED at the runner level
# before assertions ever execute. This file exists for completeness.
set -euo pipefail

# Output file from the workflow's command step
if [[ ! -s .wheel/outputs/echo-ok.txt ]]; then
  echo "FAIL: .wheel/outputs/echo-ok.txt missing or empty" >&2
  exit 1
fi
echo "PASS: workflow ran end-to-end against the configured 3rd-party provider"
exit 0
