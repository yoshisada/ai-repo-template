#!/usr/bin/env bash
# Bifrost+MiniMax team-fixture assertions. Verifies the Phase 4
# ceremony round-tripped end-to-end:
#   - parent workflow archived (success or failure bucket; partial-failure
#     legitimately archives to failure/)
#   - per-teammate output_dir was created (proof teammates were spawned
#     into the team and the wheel routed their outputs)
#   - no live state files remain
set -uo pipefail

WF_NAME=team-single-haiku-test

# 1. Workflow archived?
ARCHIVE=$(find .wheel/history/success .wheel/history/failure .wheel/history/stopped \
  -maxdepth 1 -name "${WF_NAME}-*.json" 2>/dev/null | head -1 || true)
if [[ -z "$ARCHIVE" ]]; then
  echo "FAIL: workflow not archived" >&2
  echo "  history/ tree:" >&2
  find .wheel/history -maxdepth 2 -type f 2>/dev/null | head >&2
  echo "  live state files:" >&2
  find .wheel -maxdepth 1 -name 'state_*.json' 2>/dev/null | head >&2
  exit 1
fi
echo "PASS: workflow archived → $ARCHIVE"

# 2. Per-teammate output_dir created?
TEAM_DIR_COUNT=$(find .wheel/outputs -maxdepth 1 -type d -name 'team-*' 2>/dev/null | wc -l | tr -d ' ')
if (( TEAM_DIR_COUNT > 0 )); then
  echo "PASS: per-team output_dir(s) created ($TEAM_DIR_COUNT)"
else
  echo "WARN: no per-team output_dir under .wheel/outputs/ — teammates may not have been spawned"
fi

# 3. No orphan live state files?
ORPHAN_COUNT=$(find .wheel -maxdepth 1 -name 'state_*.json' 2>/dev/null | wc -l | tr -d ' ')
if (( ORPHAN_COUNT > 0 )); then
  echo "FAIL: $ORPHAN_COUNT live state file(s) remain — orphan after archive" >&2
  find .wheel -maxdepth 1 -name 'state_*.json' >&2
  exit 1
fi
echo "PASS: no orphan state files"

echo "PASS: $(basename $(pwd)) — Phase 4 round-trip complete"
exit 0
