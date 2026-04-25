#!/usr/bin/env bash
# T015 — Pure-shell unit tests for plugin-wheel/lib/registry.sh::_internal_path_parse
# (and the public build_session_registry envelope).
#
# Covers:
#   (a) empty PATH → empty plugins map
#   (b) one valid plugin entry → one map entry, name from plugin.json
#   (c) duplicate entries (override + cache) → first-occurrence wins
#   (d) missing plugin.json → entry skipped (cannot resolve a name without manifest)
#   (e) plugin.json missing .name field → directory-basename fallback + stderr warning
#   (f) self-bootstrap injects wheel from BASH_SOURCE if missing
#   (g) idempotence — two calls return identical plugins map (ignoring built_at)
#   (h) FR-F1-2 envelope shape: schema_version, source, fallback_used, plugins
#
# Exits 0 on all-pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REGISTRY="${REPO_ROOT}/plugin-wheel/lib/registry.sh"

if [[ ! -f "$REGISTRY" ]]; then
  echo "FAIL: registry.sh not found at $REGISTRY" >&2
  exit 1
fi

pass=0
fail=0
assert_pass() { pass=$((pass + 1)); echo "PASS: $1"; }
assert_fail() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Build a sandbox fake plugins layout under a tmpdir.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/registry-path-parse-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

scaffold_plugin() {
  # $1 = plugin_dir (will host /bin and /.claude-plugin/plugin.json)
  # $2 = plugin name (or empty to write a manifest with no .name)
  local plugin_dir="$1"
  local plugin_name="$2"
  mkdir -p "${plugin_dir}/bin" "${plugin_dir}/.claude-plugin"
  if [[ -z "$plugin_name" ]]; then
    echo '{"version":"0.0.1"}' >"${plugin_dir}/.claude-plugin/plugin.json"
  else
    printf '{"name":"%s","version":"0.0.1"}\n' "$plugin_name" >"${plugin_dir}/.claude-plugin/plugin.json"
  fi
}

# Capture an absolute path to bash so we can invoke it after PATH override.
BASH_BIN="$(command -v bash)"
# Build a clean PATH from the developer's environment that EXCLUDES any
# Claude plugin /bin entries — otherwise the developer's real plugins
# would surface in tests asserting against synthetic-only state. We keep
# system tool dirs (jq, awk, basename, etc.).
ORIG_PATH=$(printf '%s\n' "$PATH" | tr ':' '\n' \
  | grep -vE '\.claude/plugins/(cache|installed)|/plugin-[a-zA-Z0-9_-]+/bin$' \
  | tr '\n' ':' | sed 's/:$//')

# Common helper: parse with a controlled PATH and HOME (no contamination from
# the developer's actual ~/.claude). The test plugin paths are PREFIXED to
# the original PATH so jq/basename/etc remain available; _internal_path_parse
# only matches /bin entries whose grandparent hosts .claude-plugin/plugin.json,
# so system /usr/bin entries do NOT register as plugins (no manifest there).
run_parse() {
  local path_value="$1"
  local home_value="${2:-$TMP/empty-home}"
  mkdir -p "$home_value"
  local effective_path
  if [[ -n "$path_value" ]]; then
    effective_path="$path_value:$ORIG_PATH"
  else
    effective_path="$ORIG_PATH"
  fi
  PATH="$effective_path" HOME="$home_value" \
    "$BASH_BIN" -c "source '$REGISTRY' && _internal_path_parse"
}

run_build() {
  local path_value="$1"
  local home_value="${2:-$TMP/empty-home}"
  mkdir -p "$home_value"
  local effective_path
  if [[ -n "$path_value" ]]; then
    effective_path="$path_value:$ORIG_PATH"
  else
    effective_path="$ORIG_PATH"
  fi
  PATH="$effective_path" HOME="$home_value" \
    "$BASH_BIN" -c "source '$REGISTRY' && build_session_registry" 2>/dev/null
}

# --- (a) empty PATH ---
out=$(run_parse "")
if [[ "$out" == "{}" ]]; then
  assert_pass "(a) empty PATH → empty map"
else
  assert_fail "(a) empty PATH: got $out"
fi

# --- (b) one valid plugin entry ---
scaffold_plugin "$TMP/plug-shelf" "shelf"
out=$(run_parse "$TMP/plug-shelf/bin:/usr/bin")
if [[ "$(printf '%s\n' "$out" | jq -r '.shelf')" == "$TMP/plug-shelf" ]]; then
  assert_pass "(b) one valid entry → name=shelf, path=$TMP/plug-shelf"
else
  assert_fail "(b) one valid entry: got $out"
fi

# --- (c) duplicate (override wins) ---
scaffold_plugin "$TMP/cache/shelf" "shelf"
scaffold_plugin "$TMP/dev/shelf" "shelf"
# PATH order: override first → wins
out=$(run_parse "$TMP/dev/shelf/bin:$TMP/cache/shelf/bin")
if [[ "$(printf '%s\n' "$out" | jq -r '.shelf')" == "$TMP/dev/shelf" ]]; then
  assert_pass "(c) duplicate: override wins (PATH order)"
else
  assert_fail "(c) duplicate: got $out"
fi

# --- (d) missing plugin.json → entry skipped ---
mkdir -p "$TMP/orphan/bin"  # no .claude-plugin/plugin.json
out=$(run_parse "$TMP/orphan/bin")
if [[ "$out" == "{}" ]]; then
  assert_pass "(d) missing plugin.json → entry skipped"
else
  assert_fail "(d) missing manifest: got $out (expected {})"
fi

# --- (e) plugin.json without .name → basename fallback + stderr warning ---
scaffold_plugin "$TMP/plug-noname" ""
out=$(PATH="$TMP/plug-noname/bin:$ORIG_PATH" HOME="$TMP/empty-home" \
       "$BASH_BIN" -c "source '$REGISTRY' && _internal_path_parse" 2>"$TMP/stderr_e")
if [[ "$(printf '%s\n' "$out" | jq -r '."plug-noname"')" == "$TMP/plug-noname" ]] \
   && grep -q "missing .name field" "$TMP/stderr_e"; then
  assert_pass "(e) missing .name → basename fallback + stderr warning"
else
  assert_fail "(e) missing .name: got $out, stderr: $(cat "$TMP/stderr_e")"
fi

# --- (f) self-bootstrap (build_session_registry includes wheel even if PATH lacks it) ---
# Use empty PATH and a HOME that has no installed_plugins.json — registry should
# fall back to candidate B (which fails — no installed file), but BEFORE returning,
# build_session_registry injects wheel itself via BASH_SOURCE. Wait, B failure
# returns 1, so we wouldn't get there. Test instead with HOME pointing at a
# scaffolded installed_plugins.json that has zero plugins:
mkdir -p "$TMP/home-empty/.claude/plugins"
echo '{"plugins":{}}' >"$TMP/home-empty/.claude/plugins/installed_plugins.json"
out=$(run_build "" "$TMP/home-empty")
if printf '%s\n' "$out" | jq -e '.plugins | has("wheel")' >/dev/null 2>&1; then
  assert_pass "(f) self-bootstrap: wheel injected from BASH_SOURCE when PATH is empty"
else
  assert_fail "(f) self-bootstrap: $out"
fi

# --- (g) idempotence ---
scaffold_plugin "$TMP/plug-kiln" "kiln"
out1=$(run_parse "$TMP/plug-kiln/bin")
out2=$(run_parse "$TMP/plug-kiln/bin")
if [[ "$out1" == "$out2" ]]; then
  assert_pass "(g) idempotence: two parse calls produce identical maps"
else
  assert_fail "(g) idempotence: $out1 != $out2"
fi

# --- (h) envelope shape ---
out=$(run_build "$TMP/plug-kiln/bin" "$TMP/home-empty")
schema=$(printf '%s\n' "$out" | jq -r '.schema_version // empty')
src=$(printf '%s\n' "$out" | jq -r '.source // empty')
fb=$(printf '%s\n' "$out" | jq -r '.fallback_used | tostring')
if [[ "$schema" == "1" && -n "$src" && -n "$fb" ]] \
   && printf '%s\n' "$out" | jq -e '.plugins | has("kiln")' >/dev/null 2>&1; then
  assert_pass "(h) envelope shape: schema_version=$schema source=$src fallback_used=$fb"
else
  assert_fail "(h) envelope shape: $out"
fi

# --- Summary ---
echo ""
echo "registry-path-parse: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
