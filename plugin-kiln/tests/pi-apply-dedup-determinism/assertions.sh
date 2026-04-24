#!/usr/bin/env bash
# T025 — pi-apply-dedup-determinism assertions.
# Validates: FR-011 pi-hash stability + SC-004 byte-identical report bodies.
set -euo pipefail

shopt -s nullglob
reports=( .kiln/logs/pi-apply-*.md )

if [[ ${#reports[@]} -lt 2 ]]; then
  echo "FAIL: expected ≥2 reports from two runs, got ${#reports[@]}" >&2
  ls -la .kiln/logs/ >&2 || true
  exit 1
fi

# Sort oldest → newest by mtime, take first 2.
first=$(ls -1tr "${reports[@]}" | head -1)
second=$(ls -1tr "${reports[@]}" | sed -n '2p')

if [[ -z "$first" || -z "$second" ]]; then
  echo "FAIL: could not identify two distinct reports" >&2
  exit 1
fi

# Compare bodies after the header timestamp line.
if ! diff -u <(tail -n +2 "$first") <(tail -n +2 "$second") >/dev/null 2>&1; then
  echo "FAIL: SC-004 violated — report bodies differ between runs" >&2
  diff -u <(tail -n +2 "$first") <(tail -n +2 "$second") | head -40 >&2 || true
  exit 1
fi

# And every actionable record must carry a 12-hex pi-hash.
if ! grep -qE '^- pi-hash: `[0-9a-f]{12}`' "$first"; then
  echo "FAIL: FR-011 — no 12-char pi-hash line found" >&2
  exit 1
fi

echo "PASS: two-run report bodies byte-identical; pi-hash stability holds" >&2
exit 0
