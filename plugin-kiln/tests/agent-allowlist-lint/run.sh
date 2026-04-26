#!/usr/bin/env bash
# T022 — NFR-005 / contracts §9.3.
# Asserts lint-agent-allowlists.sh catches:
#   1. Drift in synthesizer (e.g., adds Bash) → exit 2 with diff message.
#   2. Drift in judge (e.g., adds Write) → exit 2.
#   3. Clean files → exit 0.
# Same rerooting pattern as T020.
# Substrate: tier-2 (run.sh-only).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LINT="$REPO_ROOT/plugin-kiln/scripts/research/lint-agent-allowlists.sh"
SYNTH_AGENT="$REPO_ROOT/plugin-kiln/agents/fixture-synthesizer.md"
JUDGE_AGENT="$REPO_ROOT/plugin-kiln/agents/output-quality-judge.md"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

# Inline the allowlist-check logic (parallel to lint-agent-allowlists.sh) into
# a shim that operates on a re-rooted plugin-kiln/agents/ tree.
make_shim() {
  local fakeroot="$1"
  local shim="$fakeroot/lint.sh"
  cat > "$shim" <<'EOF_SHIM'
#!/usr/bin/env bash
set -uo pipefail
FR="$1"
normalize() {
  sed -E 's/^tools:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | { grep -v '^$' || true; } \
    | paste -sd ',' - \
    | sed 's/,/, /g'
}
check() {
  local p="$1" expected="$2"
  [[ -f "$p" ]] || { echo "Bail out! missing $p" >&2; exit 2; }
  local line
  line=$(awk 'BEGIN{in_fm=0;done=0} /^---[[:space:]]*$/{if(!in_fm){in_fm=1;next}else{exit}} in_fm && /^tools:/ && !done{print;done=1}' "$p")
  if [[ -z "$line" ]]; then
    echo "Bail out! lint-agent-allowlists: ${p#$FR/} drift — expected: \"tools: $expected\"  actual: \"<no tools: line>\"" >&2
    exit 2
  fi
  local actual
  actual=$(printf '%s\n' "$line" | normalize)
  if [[ "$actual" != "$expected" ]]; then
    echo "Bail out! lint-agent-allowlists: ${p#$FR/} drift — expected: \"$expected\"  actual: \"$actual\"" >&2
    exit 2
  fi
}
check "$FR/plugin-kiln/agents/fixture-synthesizer.md" "Read, Write, SendMessage, TaskUpdate"
check "$FR/plugin-kiln/agents/output-quality-judge.md" "Read, SendMessage, TaskUpdate"
EOF_SHIM
  chmod +x "$shim"
  printf '%s' "$shim"
}

setup_fakeroot() {
  local d="$1"
  mkdir -p "$d/plugin-kiln/agents"
  cp "$SYNTH_AGENT" "$d/plugin-kiln/agents/fixture-synthesizer.md"
  cp "$JUDGE_AGENT" "$d/plugin-kiln/agents/output-quality-judge.md"
}

# Case 1: clean copies → exit 0.
case_clean() {
  local d="$TMP/clean"; setup_fakeroot "$d"
  local shim; shim=$(make_shim "$d")
  bash "$shim" "$d" >/dev/null 2>"$TMP/err_clean"
  [[ "$?" == "0" ]]
}
assert_pass "Clean copies → exit 0" case_clean

# Case 2: synth drift (adds Bash) → exit 2 with drift message.
case_synth_drift() {
  local d="$TMP/synth-drift"; setup_fakeroot "$d"
  sed -i.bak 's/^tools: Read, Write, SendMessage, TaskUpdate$/tools: Read, Write, Bash, SendMessage, TaskUpdate/' "$d/plugin-kiln/agents/fixture-synthesizer.md"
  local shim; shim=$(make_shim "$d")
  bash "$shim" "$d" >/dev/null 2>"$TMP/err_synth"
  local rc=$?
  [[ "$rc" == "2" ]] && grep -q -F 'drift' "$TMP/err_synth" && grep -q -F 'expected' "$TMP/err_synth"
}
assert_pass "Synth drift (added Bash) → exit 2 + diff msg" case_synth_drift

# Case 3: judge drift (adds Write) → exit 2.
case_judge_drift() {
  local d="$TMP/judge-drift"; setup_fakeroot "$d"
  sed -i.bak 's/^tools: Read, SendMessage, TaskUpdate$/tools: Read, Write, SendMessage, TaskUpdate/' "$d/plugin-kiln/agents/output-quality-judge.md"
  local shim; shim=$(make_shim "$d")
  bash "$shim" "$d" >/dev/null 2>"$TMP/err_judge"
  local rc=$?
  [[ "$rc" == "2" ]] && grep -q -F 'output-quality-judge.md drift' "$TMP/err_judge"
}
assert_pass "Judge drift (added Write) → exit 2 + drift msg" case_judge_drift

# Case 4: missing tools: line entirely → exit 2.
case_missing_tools_line() {
  local d="$TMP/no-tools"; setup_fakeroot "$d"
  sed -i.bak '/^tools:/d' "$d/plugin-kiln/agents/fixture-synthesizer.md"
  local shim; shim=$(make_shim "$d")
  bash "$shim" "$d" >/dev/null 2>"$TMP/err_missing"
  [[ "$?" == "2" ]]
}
assert_pass "Missing tools: line → exit 2" case_missing_tools_line

# Case 5: live lint against the real repo agents → exit 0.
case_live_lint() {
  bash "$LINT" >/dev/null 2>&1
}
assert_pass "Live lint against committed agents → exit 0" case_live_lint

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
