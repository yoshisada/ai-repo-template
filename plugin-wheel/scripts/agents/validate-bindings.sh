#!/usr/bin/env bash
# validate-bindings.sh — validate plugin manifest agent_bindings against closed verb namespace.
#
# Per contracts/interfaces.md §3 (FR-A-7) — refuses install/lint when any verb in
# `agent_bindings:` is not in `plugin-wheel/scripts/agents/verbs/_index.json`.
#
# Usage:
#   plugin-wheel/scripts/agents/validate-bindings.sh <plugin-manifest.json>
#
# Exit codes (per contract):
#   0  — manifest is valid (or `agent_bindings:` absent — no-op)
#   1  — manifest path does not exist or is malformed JSON
#   4  — at least one verb in agent_bindings: is not in the closed namespace
#
# Stderr: human-readable diagnostic on non-zero exit. Never silent.

set -euo pipefail

die() {
  local code="$1"; shift
  echo "validate-bindings.sh: $*" >&2
  exit "$code"
}

MANIFEST="${1:-}"
[[ -z "$MANIFEST" ]] && die 1 "missing argument — usage: validate-bindings.sh <plugin-manifest.json>"
[[ ! -f "$MANIFEST" ]] && die 1 "manifest not found: $MANIFEST"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBS_INDEX="${SCRIPT_DIR}/verbs/_index.json"
[[ ! -f "$VERBS_INDEX" ]] && die 1 "verb index missing: $VERBS_INDEX"

# Validate manifest is parseable JSON.
if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  die 1 "manifest is not valid JSON: $MANIFEST"
fi

# No agent_bindings — valid no-op.
if ! jq -e '.agent_bindings' "$MANIFEST" >/dev/null 2>&1; then
  exit 0
fi

# Closed verb namespace as JSON array.
ALLOWED="$(jq -c '.verbs' "$VERBS_INDEX")"
[[ -z "$ALLOWED" || "$ALLOWED" == "null" ]] && die 1 "verb index malformed (no .verbs array): $VERBS_INDEX"

# Walk every (agent, verb) pair and find any verb not in ALLOWED.
# Output: one line per offender — "<agent>\t<verb>"
OFFENDERS="$(jq -r --argjson allowed "$ALLOWED" '
  .agent_bindings // {}
  | to_entries[]
  | .key as $agent
  | (.value.verbs // {}) | to_entries[]
  | .key as $verb
  | select(($allowed | index($verb)) | not)
  | "\($agent)\t\($verb)"
' "$MANIFEST")"

if [[ -n "$OFFENDERS" ]]; then
  while IFS=$'\t' read -r agent verb; do
    [[ -z "$agent" ]] && continue
    closed_list="$(jq -r '.verbs | join(", ")' "$VERBS_INDEX")"
    echo "validate-bindings.sh: unknown verb '$verb' for agent '$agent' — closed namespace: $closed_list" >&2
  done <<<"$OFFENDERS"
  exit 4
fi

exit 0
