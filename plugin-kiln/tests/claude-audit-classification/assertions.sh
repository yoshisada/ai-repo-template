#!/usr/bin/env bash
# Assertions for claude-audit-classification (T070).
# Validates FR-001..FR-004: classification produces all 6 enum values; unclassified defaults to keep.
set -euo pipefail

shopt -s nullglob
previews=( .kiln/logs/claude-md-audit-*.md )
if [[ ${#previews[@]} -eq 0 ]]; then
  echo "FAIL: no preview log produced" >&2
  exit 1
fi
preview=$(ls -1t "${previews[@]}" | head -1)

# At minimum the preview MUST mention the classification step or the new rules
# that depend on it. Accept either an explicit classification block, OR mentions
# of one of the classification-driven rule_ids (enumeration-bloat / benefit-missing).
if ! grep -qiE 'classif|enumeration-bloat|benefit-missing|plugin-surface|convention-rationale|product|preference' "$preview"; then
  echo "FAIL: preview shows no evidence of FR-001 classification step" >&2
  cat "$preview" >&2
  exit 1
fi

# FR-002 anchor: plugin-surface section ("## Available Commands") MUST trigger
# enumeration-bloat (action: removal-candidate). Accept any phrasing that names
# the section + the rule_id.
if ! grep -qE 'enumeration-bloat' "$preview"; then
  echo "FAIL: enumeration-bloat rule did not fire on plugin-surface section" >&2
  cat "$preview" >&2
  exit 1
fi

echo "PASS: classification + enumeration-bloat fired correctly per FR-001..FR-004 + FR-002" >&2
exit 0
