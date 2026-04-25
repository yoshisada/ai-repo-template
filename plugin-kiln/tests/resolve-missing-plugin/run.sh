#!/usr/bin/env bash
# T037 — resolve-missing-plugin: FR-F3-3 missing dep → loud failure.
#
# Asserts that running validate-workflow.sh against a workflow declaring
# requires_plugins: ["nonexistent"]:
#   (a) exits non-zero
#   (b) emits the documented FR-F3-3 error text on stderr
#   (c) does NOT create a state file (state directory has no state_*.json
#       attributable to this run)
#   (d) writes the diagnostic snapshot under .wheel/state/registry-failed-*.json

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VALIDATE="${REPO_ROOT}/plugin-wheel/bin/validate-workflow.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/resolve-missing-plugin-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p "${TMP}/.wheel" "${TMP}/workflows"
cat >"${TMP}/workflows/needs-ghost.json" <<'EOF'
{
  "name": "needs-ghost",
  "requires_plugins": ["nonexistent-plugin-xyz"],
  "steps": [
    {"id":"a","type":"command","command":"echo ok"}
  ]
}
EOF

# Snapshot existing state files under .wheel/ before the test (none expected).
preexisting=$(find "${TMP}/.wheel" -name 'state_*.json' 2>/dev/null | wc -l | tr -d ' ')

stderr_capture="${TMP}/stderr"
rc=0
( cd "$TMP" && bash "$VALIDATE" needs-ghost ) >/dev/null 2>"$stderr_capture" || rc=$?

# (a) exit non-zero
if [[ "$rc" -ne 0 ]]; then
  ok "(a) validate-workflow.sh exited non-zero ($rc) on missing plugin"
else
  nok "(a) expected non-zero exit, got $rc"
fi

# (b) documented FR-F3-3 error text
expected="Workflow 'needs-ghost' requires plugin 'nonexistent-plugin-xyz', but 'nonexistent-plugin-xyz' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir."
if grep -qF "$expected" "$stderr_capture"; then
  ok "(b) documented FR-F3-3 error text emitted"
else
  nok "(b) FR-F3-3 error text not found; stderr was: $(cat "$stderr_capture")"
fi

# (c) NO state file created
postcount=$(find "${TMP}/.wheel" -name 'state_*.json' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$postcount" == "$preexisting" ]]; then
  ok "(c) no state file created on resolver failure (count: $postcount)"
else
  nok "(c) state file created despite resolver failure (count went $preexisting → $postcount)"
fi

# (d) diagnostic snapshot under .wheel/state/registry-failed-*.json
snapshots=$(find "${TMP}/.wheel/state" -name 'registry-failed-*.json' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$snapshots" -ge 1 ]]; then
  ok "(d) diagnostic snapshot retained on failure ($snapshots file(s))"
else
  nok "(d) no diagnostic snapshot under .wheel/state/registry-failed-*.json"
fi

echo
echo "resolve-missing-plugin: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
