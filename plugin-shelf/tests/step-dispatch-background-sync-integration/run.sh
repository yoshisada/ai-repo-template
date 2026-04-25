#!/usr/bin/env bash
# T097 — Integration test for FR-E2 wrapper state-file semantic equivalence.
#
# Contract §6 Tests: "the workflow that calls the wrapper completes with the
# same state-file shape as before batching (semantic equivalence of T092)".
#
# A pure-shell harness can't drive the real LLM-in-the-loop dispatch, so the
# semantic-equivalence assertion is reframed as: running the WRAPPER once
# produces the SAME observable side-effects as running the two pre-batched
# helpers (`shelf-counter.sh increment-and-decide` then `append-bg-log.sh`)
# back-to-back. If the wrapper preserves all observable side-effects, the
# upstream state-file shape stays semantically equivalent.
#
# Side-effects compared:
#   1. Counter mutation in $SHELF_CONFIG (before -> after delta)
#   2. Log line appended to $BG_LOG_DIR/report-issue-bg-<date>.md
#   3. Final stdout JSON shape (the parseable success signal that the
#      sub-agent uses to decide ACTION = increment | full-sync)
#   4. Exit code (0 on happy path)
#
# Also verifies T092's workflow-JSON edit:
#   5. plugin-kiln/workflows/kiln-report-issue.json's dispatch-background-sync
#      step now references the wrapper (not the legacy 2-call chain).
#   6. The workflow JSON parses + validates against minimal schema expectations.

set -e
set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WRAPPER="${REPO_ROOT}/plugin-shelf/scripts/step-dispatch-background-sync.sh"
COUNTER_SH="${REPO_ROOT}/plugin-shelf/scripts/shelf-counter.sh"
APPEND_LOG_SH="${REPO_ROOT}/plugin-shelf/scripts/append-bg-log.sh"
WORKFLOW_JSON="${REPO_ROOT}/plugin-kiln/workflows/kiln-report-issue.json"

TMP="$(mktemp -d -t themeE-integration-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
pass() { printf "  PASS %s\n" "$1"; }
fail() { printf "  FAIL %s: %s\n" "$1" "$2"; FAIL=1; }

# --- Build pre-batched baseline (Test A) ---
# Run shelf-counter.sh increment-and-decide + append-bg-log.sh manually,
# capture observable side-effects.
echo "Test A: baseline — pre-batched 2-call chain side-effects"
SHELF_A="${TMP}/baseline/.shelf-config"
LOG_A="${TMP}/baseline/logs"
mkdir -p "${TMP}/baseline" "${LOG_A}"
cat > "$SHELF_A" <<EOF
shelf_full_sync_counter = 0
shelf_full_sync_threshold = 10
EOF

SHELF_CONFIG="$SHELF_A" LOCK_FILE="${SHELF_A}.lock" \
  COUNTER_OUT="$(SHELF_CONFIG="$SHELF_A" LOCK_FILE="${SHELF_A}.lock" bash "$COUNTER_SH" increment-and-decide)"

A_BEFORE=$(printf '%s' "$COUNTER_OUT" | jq -r '.before')
A_AFTER=$(printf '%s' "$COUNTER_OUT" | jq -r '.after')
A_THRESHOLD=$(printf '%s' "$COUNTER_OUT" | jq -r '.threshold')
A_ACTION=$(printf '%s' "$COUNTER_OUT" | jq -r '.action')

BG_LOG_DIR="$LOG_A" bash "$APPEND_LOG_SH" "$A_BEFORE" "$A_AFTER" "$A_THRESHOLD" "$A_ACTION" "" >/dev/null

A_COUNTER_FINAL=$(grep -E '^shelf_full_sync_counter' "$SHELF_A" | tail -1 | awk -F= '{gsub(/[[:space:]]/,"",$2); print $2}')
A_LOG_DAY=$(date -u +%Y-%m-%d)
A_LOG_FILE="${LOG_A}/report-issue-bg-${A_LOG_DAY}.md"
A_LOG_LINE=$(grep -E 'counter_before=' "$A_LOG_FILE" | tail -1)
[ -n "$A_LOG_LINE" ] && pass "A.1 baseline log line written" || fail "A.1" "no baseline log line"
[ "$A_COUNTER_FINAL" = "1" ] && pass "A.2 baseline counter 0->1" || fail "A.2" "counter=$A_COUNTER_FINAL"

# --- Run the wrapper in identical-shape isolation (Test B) ---
echo ""
echo "Test B: wrapper — same starting state, observe side-effects"
SHELF_B="${TMP}/wrapper/.shelf-config"
LOG_B="${TMP}/wrapper/logs"
mkdir -p "${TMP}/wrapper" "${LOG_B}"
cat > "$SHELF_B" <<EOF
shelf_full_sync_counter = 0
shelf_full_sync_threshold = 10
EOF

WRAPPER_OUT=$(SHELF_CONFIG="$SHELF_B" LOCK_FILE="${SHELF_B}.lock" BG_LOG_DIR="$LOG_B" bash "$WRAPPER")
WRAPPER_FINAL_JSON=$(printf '%s\n' "$WRAPPER_OUT" | grep -E '^\{' | tail -1)
B_AFTER=$(printf '%s' "$WRAPPER_FINAL_JSON" | jq -r '.counter.after')
B_NEXT=$(printf '%s' "$WRAPPER_FINAL_JSON" | jq -r '.next_action')
B_COUNTER_FINAL=$(grep -E '^shelf_full_sync_counter' "$SHELF_B" | tail -1 | awk -F= '{gsub(/[[:space:]]/,"",$2); print $2}')
B_LOG_FILE="${LOG_B}/report-issue-bg-${A_LOG_DAY}.md"
B_LOG_LINE=$(grep -E 'counter_before=' "$B_LOG_FILE" | tail -1)
[ -n "$B_LOG_LINE" ] && pass "B.1 wrapper log line written" || fail "B.1" "no wrapper log line"
[ "$B_COUNTER_FINAL" = "1" ] && pass "B.2 wrapper counter 0->1" || fail "B.2" "counter=$B_COUNTER_FINAL"

# --- Semantic equivalence (Test C) ---
echo ""
echo "Test C: A and B produce semantically equivalent side-effects"

# 1. Counter delta identical (0 -> 1 in both)
[ "$A_COUNTER_FINAL" = "$B_COUNTER_FINAL" ] \
  && pass "C.1 counter delta equivalent ($A_COUNTER_FINAL == $B_COUNTER_FINAL)" \
  || fail "C.1" "A counter=$A_COUNTER_FINAL B counter=$B_COUNTER_FINAL"

# 2. Log line shape: same fields, same values (modulo timestamp).
# Strip the leading ISO-8601 timestamp from each line for comparison.
A_LOG_TAIL=$(printf '%s' "$A_LOG_LINE" | sed -E 's/^[^|]*\| //')
B_LOG_TAIL=$(printf '%s' "$B_LOG_LINE" | sed -E 's/^[^|]*\| //')
[ "$A_LOG_TAIL" = "$B_LOG_TAIL" ] \
  && pass "C.2 log line bodies equivalent (after stripping timestamp)" \
  || fail "C.2" "A=$A_LOG_TAIL  B=$B_LOG_TAIL"

# 3. The wrapper's next_action matches the standalone counter's action
[ "$A_ACTION" = "$B_NEXT" ] \
  && pass "C.3 next_action matches standalone .action ($A_ACTION == $B_NEXT)" \
  || fail "C.3" "A action=$A_ACTION B next_action=$B_NEXT"

# 4. Wrapper's after counter matches standalone counter's after
[ "$A_AFTER" = "$B_AFTER" ] \
  && pass "C.4 wrapper.counter.after matches standalone .after ($A_AFTER == $B_AFTER)" \
  || fail "C.4" "A=$A_AFTER B=$B_AFTER"

# --- T092 workflow-JSON sanity (Test D) ---
echo ""
echo "Test D: T092 workflow-JSON references the wrapper"

# 1. JSON parses
if jq -e . "$WORKFLOW_JSON" >/dev/null 2>&1; then
  pass "D.1 workflow JSON parses"
else
  fail "D.1" "JSON parse failure"
fi

# 2. dispatch-background-sync step exists
DBS_INSTR=$(jq -r '.steps[] | select(.id=="dispatch-background-sync") | .instruction // empty' "$WORKFLOW_JSON")
if [ -n "$DBS_INSTR" ]; then
  pass "D.2 dispatch-background-sync step present"
else
  fail "D.2" "dispatch-background-sync step missing or has empty instruction"
fi

# 3. Instruction references the wrapper script
if printf '%s' "$DBS_INSTR" | grep -q 'step-dispatch-background-sync\.sh'; then
  pass "D.3 instruction references step-dispatch-background-sync.sh"
else
  fail "D.3" "wrapper not referenced in instruction"
fi

# 4. The legacy 2-call chain (the literal pair: increment-and-decide + append-bg-log
#    BOTH back-to-back inside the sub-agent prompt) is gone. The append-bg-log
#    reference may still appear in the error-fallback step (allowed); but
#    increment-and-decide must NOT be invoked directly anymore inside the
#    sub-agent body.
SUB_PROMPT=$(printf '%s\n' "$DBS_INSTR" | awk '/----BEGIN SUBAGENT PROMPT----/,/----END SUBAGENT PROMPT----/')
SUB_INC_COUNT=$(printf '%s\n' "$SUB_PROMPT" | grep -c 'shelf-counter\.sh.*increment-and-decide' || true)
if [ "$SUB_INC_COUNT" -eq 0 ]; then
  pass "D.4 legacy increment-and-decide direct call removed from sub-agent prompt"
else
  fail "D.4" "legacy increment-and-decide still in sub-agent prompt ($SUB_INC_COUNT occurrence(s))"
fi

# 5. The wrapper invocation is INSIDE the sub-agent prompt section
SUB_WRAP_COUNT=$(printf '%s\n' "$SUB_PROMPT" | grep -c 'step-dispatch-background-sync\.sh' || true)
if [ "$SUB_WRAP_COUNT" -ge 1 ]; then
  pass "D.5 wrapper invoked inside sub-agent prompt"
else
  fail "D.5" "wrapper not invoked inside sub-agent prompt (count=$SUB_WRAP_COUNT)"
fi

# 6. The foreground Step 1 (counter read for display) is preserved — that's not
#    the batched chain, it's the foreground display-value gather.
if printf '%s' "$DBS_INSTR" | grep -q 'shelf-counter\.sh" read'; then
  pass "D.6 foreground 'shelf-counter.sh read' (display values) preserved"
else
  fail "D.6" "foreground display-value read missing"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "ALL INTEGRATION ASSERTIONS PASSED"
  exit 0
else
  echo "SOME INTEGRATION ASSERTIONS FAILED"
  exit 1
fi
