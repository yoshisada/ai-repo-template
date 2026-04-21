#!/usr/bin/env bash
# write-local-record.sh
# FR-002, FR-006, FR-014, FR-015, FR-029
#
# Reads envelope JSON from a file, renders the markdown record per FR-006
# section schema, and writes it to .kiln/fixes/<date>-<slug>.md. Ensures the
# directory exists (FR-029) and disambiguates via unique-filename.sh (FR-015).
# Slug derived via shelf's derive-proposal-slug.sh (FR-014) — script located
# through the SHELF_SCRIPTS_DIR env var (FR-025 portability; exported by the
# skill before invocation).
#
# Invocation:
#   bash write-local-record.sh <envelope_json_path>
#
# stdout: absolute path of the written file on success.
# stderr: silent on success; "write-local-record: <reason>" on failure.
# exit:
#   0 — file written; path printed.
#   1 — missing envelope, invalid JSON, missing field, or write failed.
#   2 — jq or required helper scripts not resolvable.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

envelope_path="${1:-}"
if [ -z "$envelope_path" ]; then
  printf 'write-local-record: envelope path required\n' >&2
  exit 1
fi
if [ ! -r "$envelope_path" ]; then
  printf 'write-local-record: cannot read envelope at %s\n' "$envelope_path" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'write-local-record: jq not on PATH\n' >&2
  exit 2
fi

# FR-014: slug derivation uses the shelf script resolved via SHELF_SCRIPTS_DIR.
scripts_dir="${SHELF_SCRIPTS_DIR:-}"
if [ -z "$scripts_dir" ] || [ ! -x "$scripts_dir/derive-proposal-slug.sh" ]; then
  printf 'write-local-record: SHELF_SCRIPTS_DIR must point at a dir containing derive-proposal-slug.sh (got %q)\n' "$scripts_dir" >&2
  exit 2
fi
slug_script="$scripts_dir/derive-proposal-slug.sh"
unique_script="$here/unique-filename.sh"

if [ ! -x "$unique_script" ]; then
  printf 'write-local-record: unique-filename.sh missing at %s\n' "$unique_script" >&2
  exit 2
fi

# Validate envelope JSON.
if ! jq empty "$envelope_path" >/dev/null 2>&1; then
  printf 'write-local-record: invalid JSON at %s\n' "$envelope_path" >&2
  exit 1
fi

# Extract fields. jq -r for strings; `// empty` to distinguish null from "".
issue=$(jq -r '.issue // ""'                 "$envelope_path")
root_cause=$(jq -r '.root_cause // ""'       "$envelope_path")
fix_summary=$(jq -r '.fix_summary // ""'     "$envelope_path")
commit_hash=$(jq -r '.commit_hash'           "$envelope_path")
resolves_issue=$(jq -r '.resolves_issue'     "$envelope_path")
status=$(jq -r '.status // ""'               "$envelope_path")

if [ -z "$issue" ] || [ -z "$root_cause" ] || [ -z "$fix_summary" ] || [ -z "$status" ]; then
  printf 'write-local-record: envelope missing required fields\n' >&2
  exit 1
fi
case "$status" in
  fixed|escalated) : ;;
  *) printf 'write-local-record: invalid status %q\n' "$status" >&2; exit 1 ;;
esac

# files_changed: emit one-per-line; consumed below for both the tmp file list
# (for unique-filename-style collision handling we don't need it) and the YAML
# list + "## Files changed" section.
files_changed_lines=$(jq -r '.files_changed[]? // empty' "$envelope_path")

# FR-014: derive slug from the issue sentence.
slug=$(printf '%s' "$issue" | bash "$slug_script")
if [ -z "$slug" ]; then
  printf 'write-local-record: slug derivation failed for issue %q\n' "$issue" >&2
  exit 1
fi

# FR-029: ensure .kiln/fixes/ exists.
target_dir=".kiln/fixes"
mkdir -p "$target_dir"

today=$(date -u +%Y-%m-%d)

# FR-015: collision-free basename.
basename=$(bash "$unique_script" "$target_dir" "$today" "$slug")
if [ -z "$basename" ]; then
  printf 'write-local-record: unique-filename returned empty\n' >&2
  exit 1
fi

out_path="$target_dir/$basename"
abs_out=$(cd "$(dirname "$out_path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$out_path")")

# Render the markdown per contracts/interfaces.md "Rendered markdown shape".
{
  printf -- '---\n'
  printf 'type: fix\n'
  printf 'date: %s\n' "$today"
  printf 'status: %s\n' "$status"
  if [ "$commit_hash" = "null" ] || [ -z "$commit_hash" ]; then
    printf 'commit: null\n'
  else
    printf 'commit: %s\n' "$commit_hash"
  fi
  if [ "$resolves_issue" = "null" ] || [ -z "$resolves_issue" ]; then
    printf 'resolves_issue: null\n'
  else
    printf 'resolves_issue: %s\n' "$resolves_issue"
  fi
  printf 'files_changed:\n'
  if [ -z "$files_changed_lines" ]; then
    : # empty list — printed as block below; leave empty.
  else
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '  - %s\n' "$line"
    done <<< "$files_changed_lines"
  fi
  printf 'tags: []\n'
  printf -- '---\n'
  printf '\n'
  printf '## Issue\n%s\n\n' "$issue"
  printf '## Root cause\n%s\n\n' "$root_cause"
  printf '## Fix\n%s\n\n' "$fix_summary"
  printf '## Files changed\n'
  if [ -z "$files_changed_lines" ]; then
    printf -- '_none_\n\n'
  else
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf -- '- %s\n' "$line"
    done <<< "$files_changed_lines"
    printf '\n'
  fi
  printf '## Escalation notes\n'
  if [ "$status" = "fixed" ]; then
    printf -- '_none_\n'
  else
    # For escalated records, fix_summary describes techniques tried — echo it
    # into Escalation notes so the human reader sees both the quick-view in
    # ## Fix and the expanded surface in ## Escalation notes.
    printf '%s\n' "$fix_summary"
  fi
} > "$out_path"

printf '%s\n' "$abs_out"
exit 0
