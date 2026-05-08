#!/usr/bin/env bash
set -euo pipefail
ARCHIVE=$(ls .wheel/history/{success,failure,stopped}/team-single-haiku-test-*.json 2>/dev/null | head -1 || true)
if [[ -z "$ARCHIVE" ]]; then
  echo "FAIL: workflow not archived" >&2
  ls .wheel/history/ 2>&1 | head >&2
  ls .wheel/state_*.json 2>&1 | head >&2
  exit 1
fi
echo "PASS: workflow archived → $ARCHIVE"
if [[ -f ".wheel/outputs/team-single-haiku/summary.json" ]]; then
  echo "PASS: team-wait summary at .wheel/outputs/team-single-haiku/summary.json"
else
  echo "WARN: .wheel/outputs/team-single-haiku/summary.json not present"
fi
LIVE=$(ls .wheel/state_*.json 2>/dev/null | wc -l | tr -d " ")
if [[ "$LIVE" -gt 0 ]]; then
  echo "FAIL: $LIVE live state file(s) remain — orphan after archive" >&2
  exit 1
fi
echo "PASS: no orphan state files"
echo "PASS: bifrost-minimax-team-single-haiku round-trip complete"
exit 0
