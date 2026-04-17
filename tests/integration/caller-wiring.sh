#!/usr/bin/env bash
# tests/integration/caller-wiring.sh
# Acceptance Scenarios US4#1, US4#2, US4#3 (FR-011, FR-012, FR-013, FR-014):
# each of the three caller workflows MUST contain exactly one step invoking
# shelf:propose-manifest-improvement, positioned immediately before the
# terminal step.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

fail=0

check_caller() {
  local name="$1" path="$2"
  if [ ! -f "$path" ]; then
    printf 'FAIL %s — file not found: %s\n' "$name" "$path"; fail=1; return
  fi
  if ! jq empty "$path" >/dev/null 2>&1; then
    printf 'FAIL %s — invalid JSON: %s\n' "$name" "$path"; fail=1; return
  fi

  # FR-011/012/013: exactly one step with workflow == "shelf:propose-manifest-improvement"
  local count
  count=$(jq '[.steps[] | select(.type=="workflow" and .workflow=="shelf:propose-manifest-improvement")] | length' "$path")
  if [ "$count" != "1" ]; then
    printf 'FAIL %s — expected 1 propose-manifest-improvement step, got %s\n' "$name" "$count"; fail=1; return
  fi

  # FR-014: the propose step is positioned immediately before the terminal step.
  local propose_idx terminal_idx total
  propose_idx=$(jq '[.steps | to_entries[] | select(.value.type=="workflow" and .value.workflow=="shelf:propose-manifest-improvement") | .key][0]' "$path")
  terminal_idx=$(jq '[.steps | to_entries[] | select(.value.terminal==true) | .key][0]' "$path")
  total=$(jq '.steps | length' "$path")

  if [ "$terminal_idx" = "null" ]; then
    printf 'FAIL %s — no terminal step marked\n' "$name"; fail=1; return
  fi

  if [ "$((propose_idx + 1))" != "$terminal_idx" ]; then
    printf 'FAIL %s — propose step idx=%s, terminal idx=%s (expected propose==terminal-1)\n' "$name" "$propose_idx" "$terminal_idx"; fail=1; return
  fi

  if [ "$((terminal_idx + 1))" != "$total" ]; then
    printf 'FAIL %s — terminal step idx=%s but total=%s (terminal must be the last step)\n' "$name" "$terminal_idx" "$total"; fail=1; return
  fi

  printf 'PASS %s (propose_idx=%s terminal_idx=%s/%s)\n' "$name" "$propose_idx" "$terminal_idx" "$total"
}

check_caller "report-mistake-and-sync" "$ROOT/plugin-kiln/workflows/report-mistake-and-sync.json"
check_caller "report-issue-and-sync"   "$ROOT/plugin-kiln/workflows/report-issue-and-sync.json"
check_caller "shelf-full-sync"         "$ROOT/plugin-shelf/workflows/shelf-full-sync.json"

[ "$fail" -eq 0 ]
