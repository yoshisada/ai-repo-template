#!/usr/bin/env bash
# read-sync-manifest.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §4
#
# Reads .shelf-sync.json from repo root and emits it to the wheel output path.
# If the file does not exist (cold start), emits an empty manifest structure.
#
# Output: .wheel/outputs/sync-manifest.json

set -euo pipefail

OUT=".wheel/outputs/sync-manifest.json"
MANIFEST=".shelf-sync.json"
mkdir -p .wheel/outputs

if [ -f "$MANIFEST" ]; then
  # Validate JSON and copy to output
  if jq . "$MANIFEST" > /dev/null 2>&1; then
    jq . "$MANIFEST" > "$OUT"
  else
    echo "ERROR: $MANIFEST is not valid JSON" >&2
    exit 1
  fi
else
  # Cold start — emit empty manifest
  jq -n '{
    version: "1.0",
    last_synced: null,
    issues: [],
    docs: [],
    progress_paths: []
  }' > "$OUT"
fi

echo "sync-manifest.json written (source: $([ -f "$MANIFEST" ] && echo 'existing' || echo 'cold-start'))"
