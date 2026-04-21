#!/usr/bin/env bash
# tests/integration/hallucinated-current.sh
# Acceptance Scenario US2#4 (FR-005): when `current` text does NOT appear
# verbatim in the target file, the dispatch step MUST force skip even though
# the reflect output said skip:false. No write envelope, no @inbox/open/ file.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DISPATCH="$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh"
TMP=$(mktemp -d -t hallucinated.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.wheel/outputs" "$TMP/vault/manifest/types"
cat > "$TMP/vault/manifest/types/mistake.md" <<'EOF'
---
type: mistake
---
# Real template content
- severity — enum: minor | moderate | major
EOF

# `current` text that definitely does NOT appear in the target file.
reflect=$(jq -cn \
  --arg target "@manifest/types/mistake.md" \
  --arg section "## Required frontmatter" \
  --arg current "- severity — enum: low | medium | high" \
  --arg proposed "- severity — enum: minor | moderate | major | critical" \
  --arg why "see .wheel/outputs/sync-summary.md" \
  '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
printf '%s\n' "$reflect" > "$TMP/.wheel/outputs/propose-manifest-improvement.json"

envelope=$(cd "$TMP" && VAULT_ROOT="$TMP/vault" bash "$DISPATCH" 2>/dev/null || true)

if printf '%s' "$envelope" | jq -e '.action == "skip"' >/dev/null 2>&1; then
  printf 'PASS hallucinated-current-forces-skip\n'
  exit 0
fi
printf 'FAIL hallucinated-current-forces-skip — envelope=%s\n' "$envelope"
exit 1
