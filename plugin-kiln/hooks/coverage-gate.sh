#!/bin/bash
# PostToolUse(Bash) — coverage gate.
# After a test command runs, checks that coverage >= threshold from
# .kiln/test-strategy.json (default 80). Reads coverage from
# .wheel/outputs/test-results.json (default 100 if absent → fail open).
# FAIL OPEN on hook errors — only blocks on a confirmed coverage shortfall.
# FR-COVERAGE-GATE-001

INPUT=$(cat 2>/dev/null || true)

# If no input or jq unavailable, allow
if [[ -z "$INPUT" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Only act on Bash tool
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Only act when the command looks like a test runner invocation
# Match: npm test, npx vitest, jest, vitest, yarn test, pnpm test, mocha, pytest, go test
if ! echo "$COMMAND" | grep -qE '(npm (run )?test|npx vitest|vitest( run)?|jest|yarn test|pnpm test|mocha|pytest|go test)' 2>/dev/null; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
TEST_STRATEGY="$PROJECT_DIR/.kiln/test-strategy.json"
TEST_RESULTS="$PROJECT_DIR/.wheel/outputs/test-results.json"

# Read coverage gate threshold (default 80 if file/key absent)
GATE=80
if [[ -f "$TEST_STRATEGY" ]]; then
  GATE_RAW=$(jq -r '.coverage_gate // empty' "$TEST_STRATEGY" 2>/dev/null || true)
  if [[ -n "$GATE_RAW" && "$GATE_RAW" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    GATE="$GATE_RAW"
  fi
fi

# If test-results.json absent → fail open (can't confirm a violation)
if [[ ! -f "$TEST_RESULTS" ]]; then
  exit 0
fi

# Read coverage value (default to 100 if key absent — treat as passing)
COVERAGE=$(jq -r '.coverage // empty' "$TEST_RESULTS" 2>/dev/null || true)

# If coverage field is missing or non-numeric → fail open
if [[ -z "$COVERAGE" ]] || ! echo "$COVERAGE" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  exit 0
fi

# Compare coverage < gate using bc (handle decimals)
if ! command -v bc &>/dev/null; then
  # bc unavailable — use integer comparison as fallback
  COV_INT=${COVERAGE%.*}
  GATE_INT=${GATE%.*}
  if (( COV_INT < GATE_INT )); then
    cat >&2 <<EOF
COVERAGE GATE FAIL: ${COVERAGE}% < ${GATE}% required

Increase test coverage before proceeding.
Gate threshold set in .kiln/test-strategy.json (coverage_gate: ${GATE}).
Current results from .wheel/outputs/test-results.json (coverage: ${COVERAGE}).
EOF
    exit 2
  fi
  exit 0
fi

if (( $(echo "$COVERAGE < $GATE" | bc -l) )); then
  cat >&2 <<EOF
COVERAGE GATE FAIL: ${COVERAGE}% < ${GATE}% required

Increase test coverage before proceeding.
Gate threshold set in .kiln/test-strategy.json (coverage_gate: ${GATE}).
Current results from .wheel/outputs/test-results.json (coverage: ${COVERAGE}).
EOF
  exit 2
fi

exit 0
