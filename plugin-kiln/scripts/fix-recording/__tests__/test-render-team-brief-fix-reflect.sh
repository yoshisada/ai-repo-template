#!/usr/bin/env bash
# test-render-team-brief-fix-reflect.sh
# Tests FR-025, FR-027, FR-028 for the fix-reflect kind.
# Acceptance: US7 #1 — brief only contains envelope + static text; anchors survive.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../render-team-brief.sh"

template=$(cat <<'TPL'
You are the reflector for team fix-reflect ({{TEAM_KIND}}).

1. Read envelope at {{ENVELOPE_PATH}}.
2. Use {{SCRIPTS_DIR}}/validate-reflect-output.sh to validate output.
3. Use {{SCRIPTS_DIR}}/check-manifest-target-exists.sh for the exact-patch gate.
4. Use {{SCRIPTS_DIR}}/derive-proposal-slug.sh to derive a proposal slug.
5. Target `@inbox/open/{{DATE}}-manifest-improvement-<slug>.md`.
TPL
)

rendered=$(printf '%s\n' "$template" | bash "$script" \
  --envelope-path "/abs/envelope.json" \
  --scripts-dir "/plugin/cache/plugin-shelf/scripts" \
  --slug "any-slug" \
  --date "2026-04-20" \
  --project-name "" \
  --team-kind "fix-reflect")

if printf '%s' "$rendered" | grep -E -q '\{\{[A-Z_]+\}\}'; then
  printf 'FAIL: placeholder leaked through rendering\n%s\n' "$rendered" >&2
  exit 1
fi

for anchor in \
  "Read envelope at /abs/envelope.json" \
  "/plugin/cache/plugin-shelf/scripts/validate-reflect-output.sh" \
  "/plugin/cache/plugin-shelf/scripts/check-manifest-target-exists.sh" \
  "/plugin/cache/plugin-shelf/scripts/derive-proposal-slug.sh" \
  "@inbox/open/2026-04-20-manifest-improvement-"
do
  if ! printf '%s' "$rendered" | grep -Fq "$anchor"; then
    printf 'FAIL: anchor %q missing\n' "$anchor" >&2
    exit 1
  fi
done

exit 0
