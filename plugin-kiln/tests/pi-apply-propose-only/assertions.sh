#!/usr/bin/env bash
# T026 — pi-apply-propose-only assertions.
# Validates: FR-010 — skill must NEVER write to plugin-kiln/skills/ or plugin-kiln/agents/.
set -euo pipefail

CANARY="PROPOSE_ONLY_CANARY_DO_NOT_EDIT"
TARGET="plugin-kiln/agents/prd-auditor.md"

if [[ ! -f "$TARGET" ]]; then
  echo "FAIL: $TARGET was deleted — FR-010 violation" >&2
  exit 1
fi

if ! grep -qF "$CANARY" "$TARGET"; then
  echo "FAIL: canary '$CANARY' missing from $TARGET — skill modified the file" >&2
  cat "$TARGET" >&2
  exit 1
fi

# Also confirm the actionable text proposed in the retro did NOT get written.
if grep -qF 'this text must never land in the file.' "$TARGET"; then
  echo "FAIL: proposed text landed in target file — FR-010 propose-don't-apply violated" >&2
  exit 1
fi

# A report MUST exist.
shopt -s nullglob
reports=( .kiln/logs/pi-apply-*.md )
if [[ ${#reports[@]} -eq 0 ]]; then
  echo "FAIL: no preview report written" >&2
  exit 1
fi

echo "PASS: canary preserved; no write to plugin-kiln/agents/; report written" >&2
exit 0
