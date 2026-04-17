#!/usr/bin/env bash
# tests/integration/ungrounded-why.sh
# Spec edge case "Generic why" (FR-006): when the `why` field contains no
# run-evidence token (no path, no .wheel/ reference, no filename extension),
# the dispatch step MUST force skip.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DISPATCH="$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh"
TMP=$(mktemp -d -t ungrounded.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.wheel/outputs" "$TMP/vault/manifest/types"
cat > "$TMP/vault/manifest/types/mistake.md" <<'EOF'
---
type: mistake
---
# Template
- severity — enum: minor | moderate | major
EOF

reflect=$(jq -cn \
  --arg target "@manifest/types/mistake.md" \
  --arg section "top" \
  --arg current "- severity — enum: minor | moderate | major" \
  --arg proposed "- severity — enum: minor | moderate | major | critical" \
  --arg why "this could probably be better" \
  '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
printf '%s\n' "$reflect" > "$TMP/.wheel/outputs/propose-manifest-improvement.json"

envelope=$(cd "$TMP" && VAULT_ROOT="$TMP/vault" bash "$DISPATCH" 2>/dev/null || true)

if printf '%s' "$envelope" | jq -e '.action == "skip"' >/dev/null 2>&1; then
  printf 'PASS ungrounded-why-forces-skip\n'
  exit 0
fi
printf 'FAIL ungrounded-why-forces-skip — envelope=%s\n' "$envelope"
exit 1
