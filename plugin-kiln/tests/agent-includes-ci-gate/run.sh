#!/usr/bin/env bash
# SC-2 fixture for the include CI gate (FR-B-7).
# Validates: mutating a source file in _src/ without re-running build causes
# check-compiled.sh to exit non-zero with the file name in stderr; running
# build-all.sh restores parity and check-compiled.sh exits 0.
#
# Substrate: tier-2 (run.sh-only). Invoke via `bash plugin-kiln/tests/agent-includes-ci-gate/run.sh`.
# Exit 0 on PASS, non-zero on FAIL. Last line is a PASS/FAIL summary.
#
# This fixture mutates a real _src/<role>.md file in-place and restores it on
# exit (success OR failure) via trap. It does NOT touch git state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SRC_FILE="$REPO_ROOT/plugin-kiln/agents/_src/qa-engineer.md"
COMPILED_FILE="$REPO_ROOT/plugin-kiln/agents/qa-engineer.md"
BUILD_SH="$REPO_ROOT/plugin-kiln/scripts/agent-includes/build-all.sh"
CHECK_SH="$REPO_ROOT/plugin-kiln/scripts/agent-includes/check-compiled.sh"

if [[ ! -f "$SRC_FILE" ]]; then
  echo "FAIL: source fixture missing — $SRC_FILE"
  exit 2
fi

ORIG_SRC=$(mktemp)
ORIG_COMPILED=$(mktemp)
cp "$SRC_FILE" "$ORIG_SRC"
cp "$COMPILED_FILE" "$ORIG_COMPILED"

cleanup() {
  cp "$ORIG_SRC" "$SRC_FILE"
  cp "$ORIG_COMPILED" "$COMPILED_FILE"
  rm -f "$ORIG_SRC" "$ORIG_COMPILED"
}
trap cleanup EXIT

PASS=0
FAIL=0

# ---------- Step 1: baseline OK — committed compiled matches build(sources) ----------
if "$CHECK_SH" >/dev/null 2>&1; then
  PASS=$((PASS + 1))
  echo "  pass  baseline check-compiled.sh exits 0"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  baseline check-compiled.sh expected 0 but failed"
fi

# ---------- Step 2: mutate _src/ without rebuilding → check fails with file name ----------
echo "" >> "$SRC_FILE"
echo "<!-- mutation marker for ci-gate fixture -->" >> "$SRC_FILE"

err_output=$("$CHECK_SH" 2>&1 >/dev/null)
exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$err_output" | grep -q 'qa-engineer.md'; then
  PASS=$((PASS + 1))
  echo "  pass  source mutation without rebuild → check exits non-zero with file name"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  source mutation: expected non-zero exit + qa-engineer.md in stderr (exit=$exit_code, stderr=$err_output)"
fi

# ---------- Step 3: rebuild → check passes again ----------
"$BUILD_SH" >/dev/null 2>&1
if "$CHECK_SH" >/dev/null 2>&1; then
  PASS=$((PASS + 1))
  echo "  pass  after rebuild, check-compiled.sh exits 0"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  after rebuild, check-compiled.sh expected 0 but failed"
fi

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"
  exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"
  exit 1
fi
