#!/usr/bin/env bash
# tests/integration/out-of-scope.sh
# Acceptance Scenario US3#1+US3#2+US3#3 (FR-004): targets outside
# @manifest/types/*.md or @manifest/templates/*.md MUST force skip;
# valid targets inside the scope MUST produce an action:"write" envelope.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DISPATCH="$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh"
TMP=$(mktemp -d -t out-of-scope.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.wheel/outputs" "$TMP/vault/manifest/types" "$TMP/vault/manifest/templates" "$TMP/vault/manifest/systems"
cat > "$TMP/vault/manifest/types/mistake.md" <<'EOF'
- severity — enum: minor | moderate | major
EOF
cat > "$TMP/vault/manifest/systems/projects.md" <<'EOF'
Projects system overview — should not be an improvement target.
EOF

fail=0

run_case() {
  local name="$1" target="$2" current="$3" expected_action="$4"
  local reflect
  reflect=$(jq -cn \
    --arg target "$target" \
    --arg section "top" \
    --arg current "$current" \
    --arg proposed "replacement" \
    --arg why "see .wheel/outputs/shelf-full-sync-summary.md" \
    '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
  printf '%s\n' "$reflect" > "$TMP/.wheel/outputs/propose-manifest-improvement.json"
  local envelope
  envelope=$(cd "$TMP" && VAULT_ROOT="$TMP/vault" bash "$DISPATCH" 2>/dev/null || true)
  local action
  action=$(printf '%s' "$envelope" | jq -r '.action // ""' 2>/dev/null || echo "")
  if [ "$action" = "$expected_action" ]; then
    printf 'PASS %s (%s)\n' "$name" "$target"
  else
    printf 'FAIL %s — target=%s expected=%s got=%s\n' "$name" "$target" "$expected_action" "$action"
    fail=1
  fi
}

# US3#1 — shelf skill path is out of scope (not under @manifest/)
run_case "us3-1-plugin-skill" "plugin-shelf/skills/shelf-update/SKILL.md" "anything" "skip"
# Valid-looking but wrong vault subdir — @manifest/systems/ is NOT types or templates
run_case "us3-edge-systems-subdir" "@manifest/systems/projects.md" "Projects system overview" "skip"
# US3#2 — @manifest/types/ is valid
run_case "us3-2-types-valid" "@manifest/types/mistake.md" "- severity — enum: minor | moderate | major" "write"
# US3#3 — @manifest/templates/ is valid (use a seeded file)
cat > "$TMP/vault/manifest/templates/about.md" <<'EOF'
About template — section placeholder.
EOF
run_case "us3-3-templates-valid" "@manifest/templates/about.md" "About template — section placeholder." "write"

[ "$fail" -eq 0 ]
