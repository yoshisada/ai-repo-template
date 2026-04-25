#!/usr/bin/env bash
# T035 — registry-plugin-dir: --plugin-dir override wins over marketplace cache.
#
# Scaffolds two competing copies of plugin-shelf:
#   - cache copy:    $TMP/home/.claude/plugins/cache/<org>/shelf/<version>/
#   - override copy: $TMP/dev/plugin-shelf/  (also has .claude-plugin/plugin.json
#                    with name=shelf and a marker file under bin/)
#
# Builds PATH with override-first ordering (per research §1.B: --plugin-dir
# prepends to PATH at session start). Asserts:
#   - registry.plugins.shelf == override path
#   - the override-only marker file is reachable under that path

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/registry-plugin-dir-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Cache copy.
CACHE_DIR="${TMP}/home/.claude/plugins/cache/yoshisada-speckit/shelf/000.001.000.000"
mkdir -p "${CACHE_DIR}/bin" "${CACHE_DIR}/.claude-plugin"
printf '{"name":"shelf","version":"000.001.000.000"}\n' >"${CACHE_DIR}/.claude-plugin/plugin.json"
echo "cache" >"${CACHE_DIR}/bin/marker.txt"

# Override copy with marker file.
OVERRIDE_DIR="${TMP}/dev/plugin-shelf-dev"
mkdir -p "${OVERRIDE_DIR}/bin" "${OVERRIDE_DIR}/.claude-plugin"
printf '{"name":"shelf","version":"dev-override"}\n' >"${OVERRIDE_DIR}/.claude-plugin/plugin.json"
echo "override" >"${OVERRIDE_DIR}/bin/marker.txt"

clean_path=$(printf '%s\n' "$PATH" | tr ':' '\n' \
  | grep -vE '\.claude/plugins/(cache|installed)|/plugin-[a-zA-Z0-9_-]+/bin$' \
  | tr '\n' ':' | sed 's/:$//')

# Override prepended → wins.
fake_path="${OVERRIDE_DIR}/bin:${CACHE_DIR}/bin:${clean_path}"
reg_json=$(PATH="$fake_path" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)

resolved_shelf=$(printf '%s\n' "$reg_json" | jq -r '.plugins.shelf // empty')
if [[ "$resolved_shelf" == "$OVERRIDE_DIR" ]]; then
  ok "override wins: shelf → $OVERRIDE_DIR"
else
  nok "override did not win: got $resolved_shelf (expected $OVERRIDE_DIR)"
fi

# Marker check: reading marker.txt from the resolved path returns "override".
marker=$(cat "${resolved_shelf}/bin/marker.txt" 2>/dev/null || echo "<unread>")
if [[ "$marker" == "override" ]]; then
  ok "override marker file reachable via resolved path"
else
  nok "marker file mismatch: got '$marker' (expected 'override')"
fi

# Sanity: invert PATH order — cache first → cache wins (PATH-order priority).
fake_path_reversed="${CACHE_DIR}/bin:${OVERRIDE_DIR}/bin:${clean_path}"
reg_json2=$(PATH="$fake_path_reversed" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)
resolved2=$(printf '%s\n' "$reg_json2" | jq -r '.plugins.shelf // empty')
if [[ "$resolved2" == "$CACHE_DIR" ]]; then
  ok "PATH-order priority: reversed PATH → cache wins"
else
  nok "PATH-order inversion failed: got $resolved2 (expected $CACHE_DIR)"
fi

echo
echo "registry-plugin-dir: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
