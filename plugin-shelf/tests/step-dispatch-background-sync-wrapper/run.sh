#!/usr/bin/env bash
# Test harness for plugin-shelf/scripts/step-dispatch-background-sync.sh
#
# Covers (per contracts/interfaces.md §6 Tests):
#   - Unit: wrapper runs end-to-end in a tmp dir, final JSON matches
#           {"step":..., "status":"ok", "actions":[...]} (I-B3).
#   - Unit: per-action log lines use LOG_PREFIX with start/ok markers (I-B2).
#   - Unit: a deliberately-failing action mid-wrapper → non-zero exit AND
#           per-action log prefix identifies WHICH action failed (I-B2).
#   - Unit: set -e + set -u invariants hold (I-B1).
#
# Isolated via $SHELF_CONFIG / $LOCK_FILE / $BG_LOG_DIR env overrides — the
# test MUST NOT touch the real .shelf-config or .kiln/logs/.
#
# Exit 0 = all tests pass; non-zero = at least one failure.

set -e
set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WRAPPER="${REPO_ROOT}/plugin-shelf/scripts/step-dispatch-background-sync.sh"
TMP="$(mktemp -d -t themeE-wrapper-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
pass() { printf "  PASS %s\n" "$1"; }
fail() { printf "  FAIL %s: %s\n" "$1" "$2"; FAIL=1; }

# Build an isolated .shelf-config with counter=0
export SHELF_CONFIG="${TMP}/.shelf-config"
export LOCK_FILE="${SHELF_CONFIG}.lock"
export BG_LOG_DIR="${TMP}/bg-logs"
cat > "$SHELF_CONFIG" <<EOF
shelf_full_sync_counter = 0
shelf_full_sync_threshold = 10
EOF

echo "Test 1: happy path — wrapper emits contract-shaped final JSON"
OUTPUT="$(bash "$WRAPPER")"
# Last stdout line before "done" should be the jq -c -n JSON. The very last line is "done".
# Extract the JSON line (2nd-from-last non-empty).
FINAL_JSON="$(printf '%s\n' "$OUTPUT" | grep -E '^\{' | tail -1)"
if [ -z "$FINAL_JSON" ]; then
  fail "1.a" "no JSON line found in stdout"
else
  pass "1.a final JSON line present"
fi

# I-B3: required fields
step_f="$(printf '%s' "$FINAL_JSON" | jq -r '.step // empty')"
status_f="$(printf '%s' "$FINAL_JSON" | jq -r '.status // empty')"
actions_count="$(printf '%s' "$FINAL_JSON" | jq -r '.actions | length // 0')"
[ "$step_f" = "dispatch-background-sync" ] && pass "1.b step field correct" || fail "1.b" "step=$step_f"
[ "$status_f" = "ok" ]                      && pass "1.c status=ok"          || fail "1.c" "status=$status_f"
[ "$actions_count" -ge 2 ]                  && pass "1.d actions list populated" || fail "1.d" "actions count=$actions_count"

# I-B2: per-action log lines with LOG_PREFIX and start/ok markers
count_start=$(printf '%s\n' "$OUTPUT" | grep -cE 'wheel:dispatch-background-sync: action=[a-z-]+ \| start' || true)
count_ok=$(printf '%s\n'    "$OUTPUT" | grep -cE 'wheel:dispatch-background-sync: action=[a-z-]+ \| ok' || true)
[ "$count_start" -ge 2 ] && pass "1.e action=X | start lines >= 2" || fail "1.e" "start lines=$count_start"
[ "$count_ok"    -ge 2 ] && pass "1.f action=X | ok lines >= 2"    || fail "1.f" "ok lines=$count_ok"

# Side-effect: counter incremented by exactly 1
new_counter="$(grep -E '^shelf_full_sync_counter[[:space:]]*=' "$SHELF_CONFIG" | tail -1 | awk -F= '{gsub(/[[:space:]]/,"",$2); print $2}')"
[ "$new_counter" = "1" ] && pass "1.g counter mutated 0 -> 1" || fail "1.g" "counter=$new_counter"

# Side-effect: bg log line present
LOG_DAY="$(date -u +%Y-%m-%d)"
LOG_FILE="${BG_LOG_DIR}/report-issue-bg-${LOG_DAY}.md"
[ -f "$LOG_FILE" ] && pass "1.h log file created" || fail "1.h" "log file $LOG_FILE missing"
grep -qE 'counter_before=0 \| counter_after=1 \| threshold=10 \| action=increment' "$LOG_FILE" \
  && pass "1.i log line shape correct" \
  || fail "1.i" "log shape mismatch: $(cat "$LOG_FILE")"

echo ""
echo "Test 2: failing action mid-wrapper — per-action prefix identifies failure"
# Reset counter to isolate test 2 from test 1
cat > "$SHELF_CONFIG" <<EOF
shelf_full_sync_counter = 0
shelf_full_sync_threshold = 10
EOF

# Break shelf-counter.sh by pointing SHELF_CONFIG at a non-writable location.
# But the script uses ensure-defaults to create-if-missing, so blocking write
# needs read-only dir. Safer: break jq's parse by redirecting shelf-counter to
# a stub that emits bad JSON via a PATH shim.
STUB_DIR="${TMP}/bad-bin"
mkdir -p "$STUB_DIR"
cat > "${STUB_DIR}/shelf-counter.sh" <<'STUB'
#!/usr/bin/env bash
echo "not-valid-json{{"
STUB
chmod +x "${STUB_DIR}/shelf-counter.sh"
# The wrapper uses ${SELF_DIR}/shelf-counter.sh — we can't easily intercept that without
# moving the real script aside. Instead, break the wrapper via a wrapper-of-the-wrapper
# that sets the SELF_DIR by running a renamed copy with a stubbed sibling.
TEST_WRAPPER_DIR="${TMP}/wrapper-copy"
mkdir -p "$TEST_WRAPPER_DIR"
cp "${REPO_ROOT}/plugin-shelf/scripts/step-dispatch-background-sync.sh" "${TEST_WRAPPER_DIR}/"
cp "${STUB_DIR}/shelf-counter.sh" "${TEST_WRAPPER_DIR}/"
# Also copy real append-bg-log so it doesn't cascade-fail action 2 (we want action 1 to fail first)
cp "${REPO_ROOT}/plugin-shelf/scripts/append-bg-log.sh" "${TEST_WRAPPER_DIR}/"

# Run the copy — shelf-counter is broken, so action 1 should fail.
set +e
FAIL_OUTPUT="$(bash "${TEST_WRAPPER_DIR}/step-dispatch-background-sync.sh" 2>&1)"
FAIL_CODE=$?
set -e

[ "$FAIL_CODE" -ne 0 ] && pass "2.a wrapper exits non-zero on broken action" || fail "2.a" "exit=$FAIL_CODE"

# The log line IMMEDIATELY before the error should be action=counter-increment-and-decide | start
# (because action 1 failed mid-way — we have a start but no matching ok).
last_start="$(printf '%s\n' "$FAIL_OUTPUT" | grep -E 'wheel:dispatch-background-sync: action=.* \| start' | tail -1 | sed -E 's/.*action=([a-z-]+).*/\1/')"
[ "$last_start" = "counter-increment-and-decide" ] \
  && pass "2.b per-action log identifies failing action: $last_start" \
  || fail "2.b" "expected counter-increment-and-decide; got $last_start"

# No final "ok" JSON should have been emitted
if printf '%s\n' "$FAIL_OUTPUT" | grep -qE '^\{.*"status":"ok"'; then
  fail "2.c" "final ok JSON emitted despite failure"
else
  pass "2.c no success JSON emitted on failure"
fi

echo ""
echo "Test 3: set -u invariant — unset var usage in wrapper body would break"
# We can't positively test set -u without modifying the wrapper. We verify
# the wrapper opens with "set -e" and "set -u" literally.
if head -30 "$WRAPPER" | grep -qE '^set -e$' && head -30 "$WRAPPER" | grep -qE '^set -u$'; then
  pass "3.a wrapper declares set -e and set -u"
else
  fail "3.a" "set -e or set -u missing from wrapper preamble"
fi
if head -30 "$WRAPPER" | grep -qE '^set -o pipefail$'; then
  pass "3.b wrapper declares set -o pipefail"
else
  fail "3.b" "set -o pipefail missing"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
