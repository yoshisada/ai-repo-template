#!/usr/bin/env bash
# test-compose-envelope.sh
# Tests FR-001 (envelope shape) and FR-026 (credential stripping).
# Acceptance scenario: US1 #1 — envelope composition after successful commit.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../compose-envelope.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Seed a repo with .kiln/qa/.env.test so compose-envelope strips its contents.
git init -q . >/dev/null 2>&1
mkdir -p .kiln/qa
printf 'QA_SECRET=topsecret\n' > .kiln/qa/.env.test

files_list=$(mktemp)
printf 'src/a.ts\nsrc/b.ts\n' > "$files_list"

fix_summary_input=$(printf 'Adjusted cookie persistence\nQA_SECRET=topsecret')
out=$(bash "$script" \
  --issue "Login flow broken" \
  --root-cause "Session cookie was cleared on navigation" \
  --fix-summary "$fix_summary_input" \
  --files-changed-file "$files_list" \
  --commit-hash "deadbeef1234" \
  --feature-spec-path "specs/auth/spec.md" \
  --resolves-issue "42" \
  --status fixed)

# 1. Parseable JSON.
if ! printf '%s' "$out" | jq . >/dev/null 2>&1; then
  printf 'FAIL: output is not valid JSON\n%s\n' "$out" >&2
  exit 1
fi

# 2. All nine fields present.
for f in issue root_cause fix_summary files_changed commit_hash feature_spec_path project_name resolves_issue status; do
  if ! printf '%s' "$out" | jq -e "has(\"$f\")" >/dev/null; then
    printf 'FAIL: missing field %s\n' "$f" >&2
    exit 1
  fi
done

# 3. status is "fixed".
if [ "$(printf '%s' "$out" | jq -r .status)" != "fixed" ]; then
  printf 'FAIL: status not "fixed"\n' >&2
  exit 1
fi

# 4. commit_hash is the supplied value (not null).
if [ "$(printf '%s' "$out" | jq -r .commit_hash)" != "deadbeef1234" ]; then
  printf 'FAIL: commit_hash mismatch\n' >&2
  exit 1
fi

# 5. files_changed is an array with two entries.
if [ "$(printf '%s' "$out" | jq '.files_changed | length')" != "2" ]; then
  printf 'FAIL: files_changed should have 2 entries\n' >&2
  exit 1
fi

# 6. fix_summary was stripped of the QA_SECRET line (FR-026).
fs=$(printf '%s' "$out" | jq -r .fix_summary)
if printf '%s' "$fs" | grep -Fq 'QA_SECRET=topsecret'; then
  printf 'FAIL: credential line was NOT stripped from fix_summary\n%s\n' "$fs" >&2
  exit 1
fi
if ! printf '%s' "$fs" | grep -Fq 'Adjusted cookie persistence'; then
  printf 'FAIL: legitimate content removed from fix_summary\n%s\n' "$fs" >&2
  exit 1
fi

# 7. project_name resolved via FR-013 (git repo basename in this tmp dir).
pn=$(printf '%s' "$out" | jq -r .project_name)
expected_pn=$(basename "$tmp")
if [ "$pn" != "$expected_pn" ]; then
  printf 'FAIL: project_name expected %q, got %q\n' "$expected_pn" "$pn" >&2
  exit 1
fi

# 8. Escalated variant: status=escalated forces commit_hash=null and allows
#    empty files_changed. (Covers FR-012.)
empty_files=$(mktemp)
: > "$empty_files"
out_esc=$(bash "$script" \
  --issue "Flaky build" \
  --root-cause "Intermittent test race" \
  --fix-summary "Tried: retry loop, seed-pin, timeout bump. None reproduced locally." \
  --files-changed-file "$empty_files" \
  --commit-hash "" \
  --feature-spec-path "" \
  --resolves-issue "" \
  --status escalated)

if [ "$(printf '%s' "$out_esc" | jq -r .commit_hash)" != "null" ]; then
  printf 'FAIL: escalated envelope must have commit_hash null\n' >&2
  exit 1
fi
if [ "$(printf '%s' "$out_esc" | jq -r .status)" != "escalated" ]; then
  printf 'FAIL: escalated envelope must have status=escalated\n' >&2
  exit 1
fi
if [ "$(printf '%s' "$out_esc" | jq '.files_changed | length')" != "0" ]; then
  printf 'FAIL: escalated envelope with empty file list should have 0-length array\n' >&2
  exit 1
fi

# 9. Invariant: status=escalated with non-empty commit_hash rejected.
set +e
bash "$script" \
  --issue "x" --root-cause "y" --fix-summary "z" \
  --files-changed-file "$empty_files" \
  --commit-hash "abc" \
  --feature-spec-path "" --resolves-issue "" \
  --status escalated >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  printf 'FAIL: escalated+commit_hash should have been rejected\n' >&2
  exit 1
fi

exit 0
