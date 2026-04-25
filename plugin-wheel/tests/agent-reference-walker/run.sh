#!/usr/bin/env bash
# T041 / SC-008 — Agent reference walker.
#
# Walks every `plugin-*/workflows/*.json` and every `plugin-kiln/skills/*/SKILL.md`,
# extracts every agent reference (`agent_path:`, `subagent_type:` — both forms),
# and asserts the resolver exits 0 on each one.
#
# Per contracts/interfaces.md §1 "Tests": "every agent_path: in every workflow JSON
# + every subagent_type/agent-reference in every kiln skill resolves through this
# resolver without exit 1."
#
# Unknown-passthrough (source=unknown) counts as a successful resolution — it's
# the designed back-compat shape, not a failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RESOLVE="${REPO_ROOT}/plugin-wheel/scripts/agents/resolve.sh"

if [[ ! -x "$RESOLVE" ]]; then
  echo "FAIL: resolver not executable at $RESOLVE" >&2
  exit 1
fi

cd "$REPO_ROOT"

references_checked=0
failed=0
declare -a failures

resolve_one() {
  local ref="$1" source="$2"
  references_checked=$((references_checked + 1))
  if ! "$RESOLVE" "$ref" >/dev/null 2>&1; then
    failed=$((failed + 1))
    failures+=("$source: '$ref'")
  fi
}

# Extract every `subagent_type`-style reference from a text file.
# Matches patterns that real callers use (backtick-wrapped, colon-separated):
#   `subagent_type`: `debugger`
#   `subagent_type`: general-purpose
#   subagent_type: "qa-engineer"
#   "subagent_type": "foo"
# Also extracts agent_path references the same way.
extract_refs() {
  local file="$1"
  # The regex anchors on the key name (subagent_type or agent_path) optionally
  # wrapped in backticks or double-quotes, followed by optional whitespace, a
  # colon, optional whitespace, optional opening quote/backtick, then captures
  # the identifier.
  python3 - "$file" <<'PY' 2>/dev/null
import re, sys
f = sys.argv[1]
with open(f, 'r', encoding='utf-8', errors='replace') as h:
    data = h.read()
# Match on either key, allowing any of the 3 quoting styles around both key and value.
pat = re.compile(
    r'''["`]?(?:subagent_type|agent_path)["`]?\s*[:=]\s*["`']?([A-Za-z][A-Za-z0-9_.\-/]*)''',
)
seen = set()
for m in pat.finditer(data):
    ref = m.group(1)
    if ref in seen:
        continue
    seen.add(ref)
    print(ref)
PY
}

# --- Walk workflow JSON files ---
while IFS= read -r wf; do
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    resolve_one "$ref" "$wf"
  done < <(extract_refs "$wf")
done < <(find plugin-*/workflows -maxdepth 2 -name '*.json' -type f 2>/dev/null | grep -v '/tests/' | sort)

# --- Walk kiln skill markdown ---
while IFS= read -r skill; do
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    resolve_one "$ref" "$skill"
  done < <(extract_refs "$skill")
done < <(find plugin-kiln/skills -name 'SKILL.md' -type f 2>/dev/null | sort)

# --- Summary ---
echo "Checked ${references_checked} agent references."
if [[ "$failed" -ne 0 ]]; then
  echo "FAIL: ${failed} reference(s) did not resolve:" >&2
  for line in "${failures[@]}"; do
    echo "  $line" >&2
  done
  exit 1
fi
echo "PASS: all ${references_checked} references resolve through the FR-A1 resolver."
