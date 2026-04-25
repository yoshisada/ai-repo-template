#!/usr/bin/env bash
# T034 — registry-marketplace-cache: NFR-F-3 install-mode coverage.
#
# Scaffolds a fake ~/.claude/plugins/cache/<org-mp>/<plugin>/<version>/
# layout under /tmp/<uuid>/, builds an isolated PATH that contains the fake
# /bin entries, sources registry.sh, and asserts:
#   - All three fake plugins (shelf, kiln, wheel) appear in the registry
#   - Each path resolves under the fake cache root (NOT the developer's real
#     ~/.claude/plugins/cache/)
#   - source = "candidate-a-path-parsing"
#
# This is the lightweight tripwire form (no live claude --print subprocess);
# the test.yaml documents the harness-type for the kiln-test orchestrator
# but the actual claim under test is registry behaviour, which is pure shell.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REGISTRY_LIB="${REPO_ROOT}/plugin-wheel/lib/registry.sh"

if [[ ! -f "$REGISTRY_LIB" ]]; then
  echo "FAIL: registry.sh missing at $REGISTRY_LIB" >&2
  exit 1
fi

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/registry-marketplace-cache-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

CACHE_ROOT="${TMP}/home/.claude/plugins/cache/yoshisada-speckit"
ORG_OFFICIAL="${TMP}/home/.claude/plugins/cache/claude-plugins-official"

# Three fake plugins under marketplace-cache layout.
for spec in "shelf:000.001.000.000" "kiln:000.001.000.000" "wheel:000.001.000.000"; do
  name="${spec%%:*}"
  version="${spec#*:}"
  pdir="${CACHE_ROOT}/${name}/${version}"
  mkdir -p "${pdir}/bin" "${pdir}/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$name" "$version" >"${pdir}/.claude-plugin/plugin.json"
done

# A second-org plugin (frontend-design)
mkdir -p "${ORG_OFFICIAL}/frontend-design/abc123/bin" "${ORG_OFFICIAL}/frontend-design/abc123/.claude-plugin"
printf '{"name":"frontend-design","version":"abc123"}\n' >"${ORG_OFFICIAL}/frontend-design/abc123/.claude-plugin/plugin.json"

# Build an isolated PATH that prefixes the fake cache /bin entries and
# preserves system tools but excludes the developer's real plugin paths.
clean_path=$(printf '%s\n' "$PATH" | tr ':' '\n' \
  | grep -vE '\.claude/plugins/(cache|installed)|/plugin-[a-zA-Z0-9_-]+/bin$' \
  | tr '\n' ':' | sed 's/:$//')

fake_path="${CACHE_ROOT}/shelf/000.001.000.000/bin"
fake_path="${fake_path}:${CACHE_ROOT}/kiln/000.001.000.000/bin"
fake_path="${fake_path}:${CACHE_ROOT}/wheel/000.001.000.000/bin"
fake_path="${fake_path}:${ORG_OFFICIAL}/frontend-design/abc123/bin"
fake_path="${fake_path}:${clean_path}"

reg_json=$(PATH="$fake_path" HOME="${TMP}/home" \
  bash -c "source '$REGISTRY_LIB' && build_session_registry" 2>/dev/null)

# --- Assertions ---
src=$(printf '%s\n' "$reg_json" | jq -r '.source')
if [[ "$src" == "candidate-a-path-parsing" ]]; then
  ok "source = candidate-a-path-parsing"
else
  nok "source = $src (expected candidate-a-path-parsing)"
fi

for name in shelf kiln wheel frontend-design; do
  path=$(printf '%s\n' "$reg_json" | jq -r --arg n "$name" '.plugins[$n] // empty')
  if [[ -z "$path" ]]; then
    nok "registry missing entry: $name"
    continue
  fi
  case "$name" in
    frontend-design)
      expected_under="${ORG_OFFICIAL}"
      ;;
    *)
      expected_under="${CACHE_ROOT}"
      ;;
  esac
  if [[ "$path" == "${expected_under}"* ]]; then
    ok "$name → $path (under fake cache root)"
  else
    nok "$name → $path (NOT under expected fake cache root ${expected_under})"
  fi
done

# Tripwire: the registry must NOT contain entries pointing at the developer's
# real cache (paths starting with /Users/ryansuematsu/.claude/plugins/cache/).
real_leak=$(printf '%s\n' "$reg_json" | jq -r '.plugins | to_entries[] | select(.value | startswith("/Users/")) | .key' || true)
if [[ -n "$real_leak" ]]; then
  nok "tripwire: real-developer-cache leak detected for: $real_leak"
else
  ok "tripwire: no real-cache contamination in registry"
fi

echo
echo "registry-marketplace-cache: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
