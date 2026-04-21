#!/usr/bin/env bash
# tests/integration/write-proposal.sh
# Acceptance Scenario US2#1+US2#2 (FR-008, FR-009, FR-010): on a valid propose
# reflect output whose `current` text is verbatim in the target file, the
# dispatch envelope is an action:"write" with:
#   - proposal_path under @inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md
#   - frontmatter keys type/target/date
#   - body_sections preserving the five fields
# (The MCP agent step, which does the actual vault write, is exercised
# end-to-end only via /wheel:run inside Claude Code; the command-step gate
# enforcement is what this integration test validates.)

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DISPATCH="$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh"
SLUG_SCRIPT="$ROOT/plugin-shelf/scripts/derive-proposal-slug.sh"
TMP=$(mktemp -d -t write-proposal.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.wheel/outputs" "$TMP/vault/manifest/types"
cat > "$TMP/vault/manifest/types/mistake.md" <<'EOF'
---
type: mistake
---
# Mistake template

## Required frontmatter

- `severity` — enum: `minor` | `moderate` | `major`
- `tags` — three-axis
EOF

CURRENT="- \`severity\` — enum: \`minor\` | \`moderate\` | \`major\`"
PROPOSED="- \`severity\` — enum: \`minor\` | \`moderate\` | \`major\` | \`critical\`"
WHY="Run /kiln:mistake produced .kiln/mistakes/2026-04-16-api-outage.md that needed a critical severity; current enum forced a false moderate."

reflect=$(jq -cn \
  --arg target "@manifest/types/mistake.md" \
  --arg section "## Required frontmatter" \
  --arg current "$CURRENT" \
  --arg proposed "$PROPOSED" \
  --arg why "$WHY" \
  '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
printf '%s\n' "$reflect" > "$TMP/.wheel/outputs/propose-manifest-improvement.json"

envelope=$(cd "$TMP" && VAULT_ROOT="$TMP/vault" bash "$DISPATCH" 2>/dev/null || true)

fail=0

if printf '%s' "$envelope" | jq -e '.action == "write"' >/dev/null 2>&1; then
  printf 'PASS action-write\n'
else
  printf 'FAIL action-write — envelope=%s\n' "$envelope"; fail=1
fi

# FR-008/FR-019 path shape
path=$(printf '%s' "$envelope" | jq -r '.proposal_path // ""')
if printf '%s' "$path" | grep -qE '^@inbox/open/[0-9]{4}-[0-9]{2}-[0-9]{2}-manifest-improvement-[a-z0-9-]+\.md$'; then
  printf 'PASS proposal-path-shape (%s)\n' "$path"
else
  printf 'FAIL proposal-path-shape — path=%s\n' "$path"; fail=1
fi

# FR-009 frontmatter keys
fm_ok=$(printf '%s' "$envelope" | jq -r '
  (.frontmatter.type == "proposal")
  and (.frontmatter.target == "@manifest/types/mistake.md")
  and (.frontmatter.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
')
if [ "$fm_ok" = "true" ]; then
  printf 'PASS frontmatter-keys\n'
else
  printf 'FAIL frontmatter-keys — envelope=%s\n' "$envelope"; fail=1
fi

# FR-009 body sections
body_ok=$(printf '%s' "$envelope" | jq -r '
  (.body_sections.target_line == "@manifest/types/mistake.md")
  and (.body_sections.section == "## Required frontmatter")
  and (.body_sections.current | contains("severity"))
  and (.body_sections.proposed | contains("critical"))
  and (.body_sections.why | contains(".kiln/mistakes/"))
')
if [ "$body_ok" = "true" ]; then
  printf 'PASS body-sections\n'
else
  printf 'FAIL body-sections — envelope=%s\n' "$envelope"; fail=1
fi

# FR-010 slug determinism — path slug must match derive-proposal-slug.sh output
expected_slug=$(printf '%s' "$WHY" | bash "$SLUG_SCRIPT" 2>/dev/null)
actual_slug=$(printf '%s' "$path" | sed -E 's|^@inbox/open/[0-9]{4}-[0-9]{2}-[0-9]{2}-manifest-improvement-||; s|\.md$||')
if [ -n "$expected_slug" ] && [ "$expected_slug" = "$actual_slug" ]; then
  printf 'PASS slug-deterministic (%s)\n' "$actual_slug"
else
  printf 'FAIL slug-deterministic — expected=%s actual=%s\n' "$expected_slug" "$actual_slug"; fail=1
fi

[ "$fail" -eq 0 ]
