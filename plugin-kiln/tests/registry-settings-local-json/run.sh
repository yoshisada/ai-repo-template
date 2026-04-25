#!/usr/bin/env bash
# T036 — registry-settings-local-json: NFR-F-3 install-mode coverage.
#
# Two scenarios:
#   (1) Candidate A path-parse: a plugin enabled in settings.local.json is
#       on PATH (because Claude Code prepended it at session start). Asserts
#       the registry resolves the project-scoped path.
#   (2) Candidate B fallback: PATH does NOT contain the project-scoped
#       plugin /bin (e.g. a sub-process inherited a stripped PATH). Asserts
#       the fallback reads installed_plugins.json + settings.local.json and
#       still surfaces the project-scoped plugin.
#
# Per research §1.C this is the same shape as marketplace cache once on
# PATH; the value-added test is (2) — settings.local.json must be read
# even when the user-level settings don't enable the plugin.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/registry-settings-local-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Project-scoped plugin install location (via --plugin-dir mode).
PROJECT_DIR="${TMP}/project"
PLUGIN_INSTALL="${PROJECT_DIR}/.local/plugins/shelf"
mkdir -p "${PLUGIN_INSTALL}/bin" "${PLUGIN_INSTALL}/.claude-plugin"
printf '{"name":"shelf","version":"local-0.0.1"}\n' >"${PLUGIN_INSTALL}/.claude-plugin/plugin.json"

# settings.local.json scoped to the project (in CWD).
mkdir -p "${PROJECT_DIR}/.claude"
cat >"${PROJECT_DIR}/.claude/settings.local.json" <<EOF
{
  "enabledPlugins": {
    "shelf@yoshisada-speckit": true
  }
}
EOF

# installed_plugins.json under the fake HOME — points at PLUGIN_INSTALL
# (this is what installed_plugins.json would look like when shelf is enabled
# from a project-scoped --plugin-dir).
mkdir -p "${TMP}/home/.claude/plugins"
cat >"${TMP}/home/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "shelf@yoshisada-speckit": [
      {
        "scope": "project",
        "installPath": "${PLUGIN_INSTALL}",
        "version": "local-0.0.1",
        "installedAt": "2026-04-24T00:00:00Z"
      }
    ]
  }
}
EOF

clean_path=$(printf '%s\n' "$PATH" | tr ':' '\n' \
  | grep -vE '\.claude/plugins/(cache|installed)|/plugin-[a-zA-Z0-9_-]+/bin$' \
  | tr '\n' ':' | sed 's/:$//')

# --- (1) Candidate A: project /bin on PATH (the normal Claude Code path) ---
fake_path="${PLUGIN_INSTALL}/bin:${clean_path}"
reg_json=$(cd "${PROJECT_DIR}" && PATH="$fake_path" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)
resolved=$(printf '%s\n' "$reg_json" | jq -r '.plugins.shelf // empty')
src=$(printf '%s\n' "$reg_json" | jq -r '.source')
if [[ "$resolved" == "$PLUGIN_INSTALL" && "$src" == "candidate-a-path-parsing" ]]; then
  ok "(1) candidate A: project-scoped shelf → $PLUGIN_INSTALL"
else
  nok "(1) candidate A: got resolved=$resolved source=$src"
fi

# --- (2) Candidate B fallback: PATH stripped, expect installed_plugins.json read ---
reg_json2=$(cd "${PROJECT_DIR}" && PATH="$clean_path" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)
resolved2=$(printf '%s\n' "$reg_json2" | jq -r '.plugins.shelf // empty')
src2=$(printf '%s\n' "$reg_json2" | jq -r '.source')
fallback2=$(printf '%s\n' "$reg_json2" | jq -r '.fallback_used | tostring')
if [[ "$resolved2" == "$PLUGIN_INSTALL" \
   && "$src2" == "candidate-b-installed-plugins-json" \
   && "$fallback2" == "true" ]]; then
  ok "(2) candidate B fallback: project-scoped shelf → $PLUGIN_INSTALL via installed_plugins.json"
else
  nok "(2) candidate B fallback: resolved=$resolved2 source=$src2 fallback_used=$fallback2"
fi

# --- (3) Disabled in settings.local.json → NOT in registry (FR-F1-3 / EC-1) ---
# Re-write settings.local.json with shelf DISABLED.
cat >"${PROJECT_DIR}/.claude/settings.local.json" <<EOF
{
  "enabledPlugins": {
    "shelf@yoshisada-speckit": false
  }
}
EOF
reg_json3=$(cd "${PROJECT_DIR}" && PATH="$clean_path" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)
resolved3=$(printf '%s\n' "$reg_json3" | jq -r '.plugins.shelf // empty')
if [[ -z "$resolved3" ]]; then
  ok "(3) disabled-in-settings.local: shelf NOT in registry (FR-F1-3)"
else
  nok "(3) disabled-in-settings.local: shelf still resolved to $resolved3 (FR-F1-3 violation)"
fi

echo
echo "registry-settings-local-json: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
