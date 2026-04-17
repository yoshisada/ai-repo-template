#!/usr/bin/env bash
# validate-reflect-output.sh
# FR-003, FR-004, FR-005, FR-006
#
# Pure validator for the reflect step output JSON. Reads the JSON file at $1
# and emits a canonicalized verdict to stdout:
#   {"verdict":"skip","reason":"<code>"}  — when any validation rule fires
#   {"verdict":"write", target, section, current, proposed, why}  — when all pass
#
# Always exits 0 on a decision (skip or write). Exits 2 only on programmer error
# (missing argument). Silent on stderr for all normal outcomes.
#
# Note: this script does NOT verify `current` text exists verbatim in the target
# file — that is FR-005's second half, handled by check-manifest-target-exists.sh
# and orchestrated by write-proposal-dispatch.sh. This module enforces the JSON
# shape + field presence + target-scope glob + why-grounding rules.

set -u
LC_ALL=C
export LC_ALL

REFLECT_OUT="${1:-}"

if [ -z "$REFLECT_OUT" ]; then
  exit 2
fi

emit_skip() {
  # FR-003/FR-004/FR-006: force-skip with a short reason code
  printf '{"verdict":"skip","reason":"%s"}\n' "$1"
  exit 0
}

# FR-018: missing / empty / unparseable -> treat as skip, exit 0 silently
if [ ! -f "$REFLECT_OUT" ]; then
  emit_skip "malformed-or-missing"
fi
if [ ! -s "$REFLECT_OUT" ]; then
  emit_skip "malformed-or-missing"
fi
if ! jq empty "$REFLECT_OUT" >/dev/null 2>&1; then
  emit_skip "malformed-or-missing"
fi

# FR-003: `skip: true` at the top level is the honest skip path
skip_val=$(jq -r '.skip // empty' "$REFLECT_OUT" 2>/dev/null || echo "")
if [ "$skip_val" = "true" ]; then
  emit_skip "agent-skip"
fi

# FR-003: require all five fields non-empty when skip is false/absent
target=$(jq -r '.target // ""' "$REFLECT_OUT")
section=$(jq -r '.section // ""' "$REFLECT_OUT")
current=$(jq -r '.current // ""' "$REFLECT_OUT")
proposed=$(jq -r '.proposed // ""' "$REFLECT_OUT")
why=$(jq -r '.why // ""' "$REFLECT_OUT")

if [ -z "$target" ] || [ -z "$section" ] || [ -z "$current" ] || [ -z "$proposed" ] || [ -z "$why" ]; then
  emit_skip "missing-field"
fi

# FR-004: clamp target to the manifest vault — @manifest/types/*.md or
# @manifest/templates/*.md. Any target outside -> force skip.
if ! printf '%s' "$target" | grep -Eq '^@manifest/(types|templates)/[A-Za-z0-9_.-]+\.md$'; then
  emit_skip "out-of-scope"
fi

# FR-006: `why` must cite a concrete run artifact. A path containing `/`, a
# `.wheel/` reference, or a filename extension counts. Generic opinions fail.
if ! printf '%s' "$why" | grep -Eq '\.wheel/|/|\.(md|json|sh|txt|yaml|yml)(\b|$)'; then
  emit_skip "why-not-grounded"
fi

# All checks passed — emit the write verdict with fields copied verbatim.
jq -n \
  --arg target "$target" \
  --arg section "$section" \
  --arg current "$current" \
  --arg proposed "$proposed" \
  --arg why "$why" \
  '{verdict:"write", target:$target, section:$section, current:$current, proposed:$proposed, why:$why}'
exit 0
