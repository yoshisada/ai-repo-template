#!/usr/bin/env bash
# T024 — pi-apply-status-classification assertions.
# Validates: FR-012 — one PI per status branch; diff rendered only for actionable.
set -euo pipefail

shopt -s nullglob
reports=( .kiln/logs/pi-apply-*.md )
[[ ${#reports[@]} -gt 0 ]] || { echo "FAIL: no report" >&2; exit 1; }
report=$(ls -1t "${reports[@]}" | head -1)

grep -qE '^Summary: 1 actionable, 1 already-applied, 1 stale' "$report" \
  || { echo "FAIL: expected 1 actionable, 1 already-applied, 1 stale" >&2; head -5 "$report" >&2; exit 1; }

# FR-012 — diff block appears in Actionable section ONLY. Count fenced-diff blocks.
diff_count=$(grep -c '^```diff$' "$report" || true)
if [[ "$diff_count" -ne 1 ]]; then
  echo "FAIL: expected exactly 1 diff block (actionable only), got $diff_count" >&2
  exit 1
fi

# The diff block must live under Actionable PIs, not under the already-applied or stale sections.
# Extract the section index of the diff block.
diff_line=$(grep -n '^```diff$' "$report" | head -1 | cut -d: -f1)
actionable_line=$(grep -n '^## Actionable PIs' "$report" | head -1 | cut -d: -f1)
applied_line=$(grep -n '^## Already-Applied PIs' "$report" | head -1 | cut -d: -f1)
if [[ -z "$actionable_line" || -z "$applied_line" || "$diff_line" -lt "$actionable_line" || "$diff_line" -ge "$applied_line" ]]; then
  echo "FAIL: diff block is not inside the Actionable PIs section" >&2
  echo "diff at $diff_line, Actionable at $actionable_line, Already-Applied at $applied_line" >&2
  exit 1
fi

echo "PASS: classification + diff-render discipline match FR-012" >&2
exit 0
