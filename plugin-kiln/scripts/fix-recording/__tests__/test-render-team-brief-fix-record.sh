#!/usr/bin/env bash
# test-render-team-brief-fix-record.sh
# Tests FR-025, FR-027, FR-028 (static template + placeholder substitution) for
# the fix-record kind. Acceptance: US1 #3 — template content parameterized only
# by envelope fields; no placeholder leakage; anchor strings present.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../render-team-brief.sh"

template=$(cat <<'TPL'
You are the recorder for team fix-record (kind={{TEAM_KIND}}).

Envelope: read envelope at {{ENVELOPE_PATH}}
Scripts: use scripts-dir {{SCRIPTS_DIR}} for any shelf-script invocation.
Slug: {{SLUG}}
Date: {{DATE}}
Project: {{PROJECT_NAME}}

Call `create_file` on {{ENVELOPE_PATH}} once.
TPL
)

rendered=$(printf '%s\n' "$template" | bash "$script" \
  --envelope-path "/abs/path/envelope.json" \
  --scripts-dir "/abs/path/shelf-scripts" \
  --slug "fix-auth-bug" \
  --date "2026-04-20" \
  --project-name "ai-repo-template" \
  --team-kind "fix-record")

# Every placeholder must have been substituted.
if printf '%s' "$rendered" | grep -E -q '\{\{[A-Z_]+\}\}'; then
  printf 'FAIL: placeholder leaked through rendering\n%s\n' "$rendered" >&2
  exit 1
fi

# Anchor strings used by the brief must survive substitution.
for anchor in "read envelope at" "scripts-dir" "create_file" "/abs/path/envelope.json" "fix-auth-bug"; do
  if ! printf '%s' "$rendered" | grep -Fq "$anchor"; then
    printf 'FAIL: anchor %q missing from rendered brief\n' "$anchor" >&2
    exit 1
  fi
done

# Missing flag -> exit 1.
set +e
printf '%s\n' "$template" | bash "$script" --envelope-path "/x" --scripts-dir "/y" --slug "z" --date "2026-01-01" --team-kind "fix-record" >/dev/null 2>&1
rc=$?
set -e
# --project-name is allowed to be empty, so omitting it should still succeed.
if [ "$rc" -ne 0 ]; then
  printf 'FAIL: empty --project-name should be accepted (FR-013 case 3)\n' >&2
  exit 1
fi

# Template with unknown placeholder -> exit 1 (authoring safety).
bad_template=$(printf 'Uses {{NOT_A_KNOWN_KEY}} which is wrong.\n')
set +e
printf '%s' "$bad_template" | bash "$script" \
  --envelope-path "/x" --scripts-dir "/y" --slug "z" --date "2026-01-01" \
  --project-name "p" --team-kind "fix-record" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  printf 'FAIL: unknown placeholder {{NOT_A_KNOWN_KEY}} should have failed\n' >&2
  exit 1
fi

exit 0
