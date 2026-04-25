#!/usr/bin/env bash
# FR-B1..FR-B3 — Theme B test harness.
#
# Runs every test under plugin-wheel/tests/model-dispatch/ and reports a
# pass/fail summary. Exit 0 iff all tests pass.
#
# Usage:
#   bash plugin-wheel/tests/model-dispatch/run.sh
#
# Individual tests are also runnable directly — see test_*.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tests=(
  "${SCRIPT_DIR}/test_resolve_model.sh"
  "${SCRIPT_DIR}/test_dispatch_agent_step_model.sh"
  "${SCRIPT_DIR}/test_model_clause.sh"
  "${SCRIPT_DIR}/test_workflow_fixtures.sh"
)

pass=0
fail=0
failures=()

for t in "${tests[@]}"; do
  name=$(basename "${t}")
  echo ""
  echo "======================================"
  echo "  ${name}"
  echo "======================================"
  if bash "${t}"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("${name}")
  fi
done

echo ""
echo "======================================"
echo "  Theme B test-suite summary"
echo "======================================"
echo "Suites: ${pass} pass, ${fail} fail"
if [[ "${fail}" -gt 0 ]]; then
  echo "Failed suites:"
  for f in "${failures[@]}"; do
    echo "  - ${f}"
  done
  exit 1
fi
exit 0
