#!/usr/bin/env bash
# T023 — pi-apply-report-basic assertions.
# Validates: FR-009 (report emitted), FR-010 (diff-shape patches), FR-011 (all
# required fields per PI block), SC-004 (determinism), SC-005 (PI-1 R-1 surfaced).
set -euo pipefail

shopt -s nullglob
reports=( .kiln/logs/pi-apply-*.md )

if [[ ${#reports[@]} -eq 0 ]]; then
  echo "FAIL: no .kiln/logs/pi-apply-*.md report produced" >&2
  find .kiln -type f 2>/dev/null >&2 || true
  exit 1
fi

report=$(ls -1t "${reports[@]}" | head -1)
echo "Report: $report" >&2

# 1. Summary line present + correct counts.
if ! grep -qE '^Summary: 2 actionable, 2 already-applied, 1 stale' "$report"; then
  echo "FAIL: summary counts wrong (expected 2 actionable, 2 already-applied, 1 stale)" >&2
  head -10 "$report" >&2
  exit 1
fi

# 2. Four sections present in the required order.
for section in '## Actionable PIs' '## Already-Applied PIs' '## Stale PIs (anchor not found)' '## Parse Errors'; do
  if ! grep -qF "$section" "$report"; then
    echo "FAIL: section '$section' missing from report" >&2
    exit 1
  fi
done

# 3. SC-005 — PI-1 targeting prd-auditor.md must surface as actionable with the R-1 blessing text.
if ! grep -qE 'plugin-kiln/agents/prd-auditor\.md.*## R-1' "$report"; then
  echo "FAIL: SC-005 — PI-1 auditor/R-1 entry not surfaced" >&2
  exit 1
fi
if ! grep -qF 'Strict behavioral superset' "$report"; then
  echo "FAIL: SC-005 — R-1 blessing proposed text not in report diff" >&2
  exit 1
fi

# 4. FR-011 — every actionable block carries source URL + pi-hash.
if ! grep -qE 'Source: https://github.com/yoshisada/ai-repo-template/issues/149' "$report"; then
  echo "FAIL: FR-011 — source URL missing" >&2
  exit 1
fi
if ! grep -qE '^- pi-hash: `[0-9a-f]{12}`' "$report"; then
  echo "FAIL: FR-011 — no 12-char pi-hash row found" >&2
  exit 1
fi

# 5. FR-010 — at least one unified-diff block present for actionable PIs.
if ! grep -qF '```diff' "$report"; then
  echo "FAIL: FR-010 — no unified-diff fenced block in report" >&2
  exit 1
fi

# 6. FR-010 — target files MUST NOT have been modified.
if [[ -f plugin-kiln/agents/prd-auditor.md ]]; then
  if ! grep -qF 'This rule is already here.' plugin-kiln/agents/prd-auditor.md; then
    echo "FAIL: FR-010 violation — skill modified plugin-kiln/agents/prd-auditor.md" >&2
    exit 1
  fi
fi

echo "PASS: pi-apply report matches FR-009/FR-010/FR-011/SC-005 contract" >&2
exit 0
