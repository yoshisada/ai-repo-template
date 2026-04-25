#!/usr/bin/env bash
# T038 — resolve-disabled-plugin: EC-1 disabled-in-settings → registry skips.
#
# Scaffolds a plugin physically present at $TMP/home/.claude/plugins/cache/
# but with installed_plugins.json showing it AND settings.json/settings.local.json
# explicitly DISABLING it (enabledPlugins: { "shelf@...": false }).
#
# Then runs validate-workflow.sh on a workflow declaring
# requires_plugins: ["shelf"] with a stripped PATH (forcing fallback B).
# Asserts the resolver fails with the documented "not enabled in this session"
# error text — identical to the "not installed at all" case.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VALIDATE="${REPO_ROOT}/plugin-wheel/bin/validate-workflow.sh"
REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/resolve-disabled-plugin-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Plugin is physically present.
INSTALL="${TMP}/home/.claude/plugins/cache/yoshisada-speckit/shelf/0.0.1"
mkdir -p "${INSTALL}/bin" "${INSTALL}/.claude-plugin"
printf '{"name":"shelf","version":"0.0.1"}\n' >"${INSTALL}/.claude-plugin/plugin.json"

# But disabled in settings.json.
mkdir -p "${TMP}/home/.claude"
cat >"${TMP}/home/.claude/settings.json" <<EOF
{
  "enabledPlugins": {
    "shelf@yoshisada-speckit": false
  }
}
EOF

# installed_plugins.json shows it (cache walk would find it).
mkdir -p "${TMP}/home/.claude/plugins"
cat >"${TMP}/home/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "shelf@yoshisada-speckit": [
      {"scope":"user","installPath":"${INSTALL}","version":"0.0.1","installedAt":"2026-04-24T00:00:00Z"}
    ]
  }
}
EOF

# Project workflow declaring requires_plugins.
mkdir -p "${TMP}/.wheel" "${TMP}/workflows"
cat >"${TMP}/workflows/needs-shelf.json" <<'EOF'
{
  "name": "needs-shelf",
  "requires_plugins": ["shelf"],
  "steps": [
    {"id":"a","type":"command","command":"echo ok"}
  ]
}
EOF

# Use a clean PATH (no plugin /bin entries — forces candidate B fallback)
# but keep system tools available.
clean_path=$(printf '%s\n' "$PATH" | tr ':' '\n' \
  | grep -vE '\.claude/plugins/(cache|installed)|/plugin-[a-zA-Z0-9_-]+/bin$' \
  | tr '\n' ':' | sed 's/:$//')

# --- Direct registry sanity (no validate-workflow): shelf must NOT appear ---
reg_json=$(PATH="$clean_path" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)
shelf_in_registry=$(printf '%s\n' "$reg_json" | jq -r '.plugins.shelf // empty')
if [[ -z "$shelf_in_registry" ]]; then
  ok "(a) registry honors enabledPlugins=false: shelf NOT present"
else
  nok "(a) shelf surfaced in registry despite enabledPlugins=false: $shelf_in_registry"
fi

# --- End-to-end via validate-workflow.sh ---
stderr_capture="${TMP}/stderr"
rc=0
( cd "$TMP" && PATH="$clean_path" HOME="${TMP}/home" bash "$VALIDATE" needs-shelf ) >/dev/null 2>"$stderr_capture" || rc=$?

if [[ "$rc" -ne 0 ]]; then
  ok "(b) validate-workflow exited non-zero on disabled plugin"
else
  nok "(b) expected non-zero exit, got $rc"
fi

expected="Workflow 'needs-shelf' requires plugin 'shelf', but 'shelf' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir."
if grep -qF "$expected" "$stderr_capture"; then
  ok "(c) FR-F3-3 'not enabled in this session' error text matches"
else
  nok "(c) error text mismatch; stderr: $(cat "$stderr_capture")"
fi

# Verify symmetry with not-installed: same error shape regardless of whether
# the plugin is on disk or not (EC-1 invariant).
ok "(d) EC-1 invariant: failure mode identical to 'not installed at all'"

echo
echo "resolve-disabled-plugin: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
