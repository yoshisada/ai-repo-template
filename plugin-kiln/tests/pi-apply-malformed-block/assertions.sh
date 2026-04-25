#!/usr/bin/env bash
# T027 — pi-apply-malformed-block assertions.
# Validates: malformed PI blocks surface under Parse Errors; other blocks continue to parse.
set -euo pipefail

shopt -s nullglob
reports=( .kiln/logs/pi-apply-*.md )
[[ ${#reports[@]} -gt 0 ]] || { echo "FAIL: no report" >&2; exit 1; }
report=$(ls -1t "${reports[@]}" | head -1)

# Parse error section must contain PI-2 with "missing field: Why".
if ! grep -qE '### #500 PI-2 — lines [0-9]+-[0-9]+' "$report"; then
  echo "FAIL: PI-2 not surfaced under Parse Errors section with line range" >&2
  cat "$report" >&2
  exit 1
fi

if ! grep -qE 'Error: missing field: Why' "$report"; then
  echo "FAIL: parse-error Error row for 'missing field: Why' not present" >&2
  exit 1
fi

# PI-1 must still have been parsed and classified (appears somewhere outside Parse Errors).
if ! grep -qE '### #500 PI-1 — plugin-kiln/agents/prd-auditor\.md' "$report"; then
  echo "FAIL: PI-1 (well-formed block) not surfaced" >&2
  exit 1
fi

# PI-1's URL line must be present (well-formed block keeps full metadata).
if ! grep -qE '^- Source: https://github.com/x/y/issues/500' "$report"; then
  echo "FAIL: PI-1 source URL missing" >&2
  exit 1
fi

echo "PASS: malformed PI-2 → Parse Errors; PI-1 still parsed" >&2
exit 0
