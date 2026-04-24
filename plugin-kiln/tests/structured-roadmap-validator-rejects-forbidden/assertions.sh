#!/usr/bin/env bash
# FR-008 / SC-006 — validator rejects forbidden sizing fields.
set -euo pipefail

if [ ! -f validator-output.txt ]; then
  echo "FAIL: validator-output.txt missing (claude didn't execute the helper)" >&2
  ls >&2
  exit 1
fi

# Each fixture should have { ok: false } and the error list should call out
# the forbidden field
check() {
  local fixture="$1" field="$2"
  if ! grep -qE "=== .*${fixture}.md ===" validator-output.txt; then
    echo "FAIL: validator didn't run against $fixture" >&2
    cat validator-output.txt >&2
    exit 1
  fi
  # The line right after the === header must contain {"ok":false with the forbidden key named
  if ! grep -F "forbidden sizing key present: ${field}" validator-output.txt >/dev/null; then
    echo "FAIL: validator did not flag ${field} as forbidden for fixture ${fixture}" >&2
    cat validator-output.txt >&2
    exit 1
  fi
done
}

check "2026-04-24-bad-human-time"  "human_time"
check "2026-04-24-bad-tshirt"       "t_shirt_size"
check "2026-04-24-bad-effort-days"  "effort_days"

# Sanity: no false positive — validator must report ok:false for every bad fixture
fail_count=$(grep -c '"ok":false' validator-output.txt || true)
if [ "$fail_count" -lt 3 ]; then
  echo "FAIL: expected at least 3 ok:false results (one per fixture), got $fail_count" >&2
  cat validator-output.txt >&2
  exit 1
fi

echo "PASS: validator rejected all three forbidden-sizing fixtures" >&2
exit 0
