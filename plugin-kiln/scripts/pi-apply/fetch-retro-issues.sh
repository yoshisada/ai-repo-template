#!/usr/bin/env bash
# FR-009: Thin wrapper around `gh issue list --label retrospective --state open --json`.
# Contract: specs/workflow-governance/contracts/interfaces.md Module 3 §fetch-retro-issues.sh
#
# Emits a JSON array sorted ascending by issue `number`. Exit 3 on `gh` failure.
#
# For test fixtures: set PI_APPLY_FETCH_STUB to a path whose contents are emitted
# verbatim in lieu of a live `gh` call. This honors the NFR-002 budget (no N+1
# calls) while keeping the test fixture's `gh` dependency deterministic.

set -euo pipefail

# FR-009: test-time stub (fixture-local `gh` replacement). Documented in
# specs/workflow-governance/tasks.md T023 — fixtures drop a canned JSON file
# and point at it via PI_APPLY_FETCH_STUB.
if [[ -n "${PI_APPLY_FETCH_STUB:-}" ]]; then
  if [[ ! -f "$PI_APPLY_FETCH_STUB" ]]; then
    echo "fetch-retro-issues.sh: PI_APPLY_FETCH_STUB points at missing file: $PI_APPLY_FETCH_STUB" >&2
    exit 3
  fi
  # Re-sort by .number to match the live path's determinism guarantee.
  jq -c 'sort_by(.number)' "$PI_APPLY_FETCH_STUB" \
    || { echo "fetch-retro-issues.sh: stub payload is not valid JSON" >&2; exit 3; }
  exit 0
fi

# Live path — requires `gh` authenticated against the current repo.
if ! command -v gh >/dev/null 2>&1; then
  echo "fetch-retro-issues.sh: gh CLI not installed" >&2
  exit 3
fi

# gh issue list returns: number, url, title, body (plus other fields we ignore).
if ! RAW=$(gh issue list --label retrospective --state open --json number,url,title,body --limit 100 2>&1); then
  echo "fetch-retro-issues.sh: gh error: $RAW" >&2
  exit 3
fi

# gh emits a JSON array; sort by number ASC for determinism.
# printf '%s' avoids bash/zsh `echo` expanding literal \n escapes inside JSON strings.
printf '%s' "$RAW" | jq -c 'sort_by(.number)'
