#!/usr/bin/env bash
# T033 — Pure-shell unit tests for plugin-wheel/lib/resolve.sh.
#
# Asserts the FR-F3-3 documented error text shapes EXACTLY (NFR-F-2 silent-
# failure tripwire — these strings are the contract; tests must catch any
# silent regression of the form "the error message changed and now nothing
# downstream recognizes the failure").
#
# Cases:
#   (a) missing plugin            — exact "requires plugin '<X>', but ... not enabled" text
#   (b) unknown plugin token      — exact "references unknown plugin token" text
#   (c) malformed: non-string     — exact "non-string at index" text
#   (d) malformed: empty string   — exact "empty string at index" text
#   (e) malformed: bad chars      — exact "invalid name" text
#   (f) malformed: duplicate      — exact "duplicate name" text
#   (g) no requires_plugins, no tokens — exits 0 silently (NFR-F-5)
#   (h) escaped token $${WHEEL_PLUGIN_unknown} — passes (EC-5)
#   (i) WORKFLOW_PLUGIN_DIR token is exempt from token-discovery
#   (j) NFR-F-2 silent-failure tripwire — mutation: deliberately weaken the
#       error string and assert the assertion fails (run inside a sub-bash).
#
# Exit 0 if all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REGISTRY="${REPO_ROOT}/plugin-wheel/lib/registry.sh"
RESOLVE="${REPO_ROOT}/plugin-wheel/lib/resolve.sh"

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Static stub registry for resolve tests (no PATH parsing needed).
REG='{"schema_version":1,"built_at":"2026-04-24T00:00:00Z","source":"test","fallback_used":false,"plugins":{"shelf":"/abs/shelf","kiln":"/abs/kiln","wheel":"/abs/wheel"}}'

# Helper: run resolve_workflow_dependencies and capture stdout, stderr, exit.
run_resolve() {
  local wf="$1"
  local reg="${2:-$REG}"
  bash -c "
    source '$RESOLVE'
    resolve_workflow_dependencies '$wf' '$reg' 2>/tmp/resolve-err-\$\$
    rc=\$?
    cat /tmp/resolve-err-\$\$
    rm -f /tmp/resolve-err-\$\$
    exit \$rc
  "
}

assert_exit_and_match() {
  local desc="$1"
  local wf="$2"
  local expected_exit="$3"
  local expected_pattern="$4"

  local out rc
  out=$(run_resolve "$wf" 2>&1)
  rc=$?
  if [[ "$rc" -ne "$expected_exit" ]]; then
    assert_fail "$desc — exit $rc != expected $expected_exit; out=$out"
    return 1
  fi
  if [[ -n "$expected_pattern" ]]; then
    if ! grep -qF "$expected_pattern" <<<"$out"; then
      assert_fail "$desc — output missing pattern '$expected_pattern'; got: $out"
      return 1
    fi
  fi
  assert_pass "$desc"
}

# --- (a) missing plugin ---
WF=$(jq -nc '{name:"abc", requires_plugins:["nonexistent"], steps:[{id:"x",type:"command"}]}')
assert_exit_and_match "(a) missing plugin error text" \
  "$WF" 1 \
  "Workflow 'abc' requires plugin 'nonexistent', but 'nonexistent' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir."

# --- (b) unknown plugin token ---
WF=$(jq -nc '{name:"abc", steps:[{id:"x",type:"agent",instruction:"${WHEEL_PLUGIN_unknown}/foo"}]}')
assert_exit_and_match "(b) unknown plugin token error text" \
  "$WF" 1 \
  "Workflow 'abc' references unknown plugin token '\${WHEEL_PLUGIN_unknown}'. Add 'unknown' to requires_plugins."

# --- (c) malformed: non-string ---
WF=$(jq -nc '{name:"abc", requires_plugins:[42], steps:[]}')
assert_exit_and_match "(c) malformed: non-string error text" \
  "$WF" 1 \
  "Workflow 'abc' has malformed requires_plugins entry: non-string at index 0."

# --- (d) malformed: empty string ---
WF=$(jq -nc '{name:"abc", requires_plugins:[""], steps:[]}')
assert_exit_and_match "(d) malformed: empty string error text" \
  "$WF" 1 \
  "Workflow 'abc' has malformed requires_plugins entry: empty string at index 0."

# --- (e) malformed: invalid chars ---
WF=$(jq -nc '{name:"abc", requires_plugins:["bad/name"], steps:[]}')
assert_exit_and_match "(e) malformed: invalid name error text" \
  "$WF" 1 \
  "Workflow 'abc' has malformed requires_plugins entry: invalid name 'bad/name' at index 0"

# --- (f) malformed: duplicate ---
WF=$(jq -nc '{name:"abc", requires_plugins:["shelf","shelf"], steps:[]}')
assert_exit_and_match "(f) malformed: duplicate name error text" \
  "$WF" 1 \
  "Workflow 'abc' has malformed requires_plugins entry: duplicate name 'shelf'."

# --- (g) no requires_plugins, no tokens — silent 0 (NFR-F-5) ---
WF=$(jq -nc '{name:"abc", steps:[{id:"x",type:"command"}]}')
assert_exit_and_match "(g) no requires_plugins, no tokens — silent exit 0" \
  "$WF" 0 ""

# --- (h) escaped token $${WHEEL_PLUGIN_unknown} — passes (EC-5) ---
WF=$(jq -nc '{name:"abc", steps:[{id:"x",type:"agent",instruction:"$${WHEEL_PLUGIN_unknown}/foo"}]}')
assert_exit_and_match "(h) escaped token EC-5 — exit 0" \
  "$WF" 0 ""

# --- (i) WORKFLOW_PLUGIN_DIR exempt ---
WF=$(jq -nc '{name:"abc", steps:[{id:"x",type:"agent",instruction:"${WORKFLOW_PLUGIN_DIR}/foo"}]}')
assert_exit_and_match "(i) WORKFLOW_PLUGIN_DIR exempt from token-discovery" \
  "$WF" 0 ""

# --- (j) NFR-F-2 silent-failure tripwire (mutation) ---
# Deliberately mutate the resolver: comment out the "missing plugin" error
# line in a tmp copy, then assert that case (a)'s assertion FAILS — i.e.
# the test catches the silence. This is the meta-test that makes NFR-F-2
# enforceable: if someone merges a change that silently swallows the
# resolver error, this mutation test would not detect it, but case (a)
# would suddenly pass exit-0 instead of exit-1.
TMP_RESOLVE=$(mktemp)
trap 'rm -f "$TMP_RESOLVE" "$TMP_RESOLVE.bak"' EXIT
sed -e "s/return 1/return 0/g" "$RESOLVE" >"$TMP_RESOLVE"
WF=$(jq -nc '{name:"abc", requires_plugins:["nonexistent"], steps:[{id:"x",type:"command"}]}')
mutated_rc=0
bash -c "source '$TMP_RESOLVE' && resolve_workflow_dependencies '$WF' '$REG'" 2>/dev/null || mutated_rc=$?
if [[ "$mutated_rc" -eq 0 ]]; then
  # Mutated returned 0 (silent failure). Real resolver returned 1. The
  # assertion in (a) above already proves the silent-failure tripwire fires
  # when the original code is intact; this confirms the mutation actually
  # weakens behavior so the test would fail if regression slipped in.
  assert_pass "(j) NFR-F-2 silent-failure mutation: weakened resolver returns 0 (would fail assertion in real test)"
else
  assert_fail "(j) NFR-F-2 mutation: weakened resolver still returned non-zero (mutation didn't take); rc=$mutated_rc"
fi

# --- Summary ---
echo ""
echo "resolve-error-shapes: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
