#!/usr/bin/env bash
# test-write-local-record.sh
# Tests FR-002, FR-006 (markdown shape), FR-014 (slug via shelf), FR-015
# (collision), FR-029 (dir creation). Acceptance scenarios:
#   US1 #1 — local record written before team spawn.
#   US1 #3 — body shape with five H2 sections in order.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../write-local-record.sh"
compose="$here/../compose-envelope.sh"
repo_root=$(cd -- "$here/../../../.." && pwd)
export SHELF_SCRIPTS_DIR="$repo_root/plugin-shelf/scripts"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q . >/dev/null 2>&1

files_list=$(mktemp)
printf 'src/a.ts\nsrc/b.ts\n' > "$files_list"

envelope=$(bash "$compose" \
  --issue "Login redirect fails after auth" \
  --root-cause "Redirect path was hardcoded to /home" \
  --fix-summary "Made redirect target configurable." \
  --files-changed-file "$files_list" \
  --commit-hash "abc123" \
  --feature-spec-path "specs/auth/spec.md" \
  --resolves-issue "42" \
  --status fixed)

envelope_path="$tmp/envelope.json"
printf '%s' "$envelope" > "$envelope_path"

out_path=$(bash "$script" "$envelope_path")
if [ ! -f "$out_path" ]; then
  printf 'FAIL: write-local-record did not produce a file; got path %q\n' "$out_path" >&2
  exit 1
fi

# Frontmatter: type: fix, status: fixed, commit: abc123.
if ! head -10 "$out_path" | grep -Fq 'type: fix'; then
  printf 'FAIL: frontmatter missing type: fix\n' >&2
  head -15 "$out_path" >&2
  exit 1
fi
if ! head -10 "$out_path" | grep -Fq 'status: fixed'; then
  printf 'FAIL: frontmatter missing status: fixed\n' >&2
  exit 1
fi
if ! head -10 "$out_path" | grep -Fq 'commit: abc123'; then
  printf 'FAIL: frontmatter missing commit: abc123\n' >&2
  exit 1
fi

# Five H2 sections in exact order.
headings=$(grep -E '^## ' "$out_path")
expected=$(printf '## Issue\n## Root cause\n## Fix\n## Files changed\n## Escalation notes')
if [ "$headings" != "$expected" ]; then
  printf 'FAIL: H2 sections out of order or missing\nGot:\n%s\nExpected:\n%s\n' "$headings" "$expected" >&2
  exit 1
fi

# Escalation notes is "_none_" for status: fixed.
esc=$(awk '/^## Escalation notes$/{flag=1;next}/^## /{flag=0}flag' "$out_path")
esc=$(printf '%s' "$esc" | sed '/^$/d')
if [ "$esc" != "_none_" ]; then
  printf 'FAIL: ## Escalation notes should be "_none_" for fixed; got %q\n' "$esc" >&2
  exit 1
fi

# FR-015: second invocation same-day same-slug disambiguates.
out_path_2=$(bash "$script" "$envelope_path")
if [ "$out_path_2" = "$out_path" ]; then
  printf 'FAIL: collision not disambiguated — same path returned twice\n' >&2
  exit 1
fi
if [[ "$(basename "$out_path_2")" != *"-2.md" ]]; then
  printf 'FAIL: second filename should end with -2.md; got %q\n' "$out_path_2" >&2
  exit 1
fi

exit 0
