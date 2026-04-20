#!/usr/bin/env bash
# compose-envelope.sh
# FR-001, FR-013, FR-026
#
# Assembles the fix envelope JSON and emits it on stdout. All nine fields are
# required and nullable where noted (see contracts/interfaces.md). Credentials
# are stripped from string fields before JSON composition (FR-026).
#
# Invocation:
#   bash compose-envelope.sh \
#     --issue "<string>" \
#     --root-cause "<string>" \
#     --fix-summary "<string>" \
#     --files-changed-file "<path>" \
#     --commit-hash "<string-or-empty>" \
#     --feature-spec-path "<string-or-empty>" \
#     --resolves-issue "<string-or-empty>" \
#     --status "fixed"|"escalated"
#
# stdout: envelope JSON (jq-compact or pretty — caller only relies on "parseable by jq").
# stderr: silent on success; "compose-envelope: <reason>" on failure.
# exit:
#   0 — valid envelope emitted.
#   1 — missing required flag, invalid status, or credential leak detected.
#   2 — `jq` not on PATH.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if ! command -v jq >/dev/null 2>&1; then
  printf 'compose-envelope: jq not on PATH\n' >&2
  exit 2
fi

issue=""
root_cause=""
fix_summary=""
files_changed_file=""
commit_hash=""
feature_spec_path=""
resolves_issue=""
status=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue)              issue="${2:-}"; shift 2 ;;
    --root-cause)         root_cause="${2:-}"; shift 2 ;;
    --fix-summary)        fix_summary="${2:-}"; shift 2 ;;
    --files-changed-file) files_changed_file="${2:-}"; shift 2 ;;
    --commit-hash)        commit_hash="${2:-}"; shift 2 ;;
    --feature-spec-path)  feature_spec_path="${2:-}"; shift 2 ;;
    --resolves-issue)     resolves_issue="${2:-}"; shift 2 ;;
    --status)             status="${2:-}"; shift 2 ;;
    *) printf 'compose-envelope: unknown flag %s\n' "$1" >&2; exit 1 ;;
  esac
done

if [ -z "$issue" ];        then printf 'compose-envelope: --issue required\n' >&2; exit 1; fi
if [ -z "$root_cause" ];   then printf 'compose-envelope: --root-cause required\n' >&2; exit 1; fi
if [ -z "$fix_summary" ];  then printf 'compose-envelope: --fix-summary required\n' >&2; exit 1; fi
if [ -z "$files_changed_file" ]; then
  printf 'compose-envelope: --files-changed-file required (may be empty file)\n' >&2
  exit 1
fi
if [ ! -e "$files_changed_file" ]; then
  printf 'compose-envelope: files-changed-file does not exist: %s\n' "$files_changed_file" >&2
  exit 1
fi
case "$status" in
  fixed|escalated) : ;;
  *) printf 'compose-envelope: --status must be "fixed" or "escalated"\n' >&2; exit 1 ;;
esac

# FR-013: resolve project_name via the internal fallback chain (never a flag).
project_name=$(bash "$here/resolve-project-name.sh" 2>/dev/null || true)

# FR-026: strip credential lines from all string fields before JSON assembly.
strip() { printf '%s' "$1" | bash "$here/strip-credentials.sh"; }
issue_s=$(strip "$issue")
root_cause_s=$(strip "$root_cause")
fix_summary_s=$(strip "$fix_summary")

# FR-001 invariant: commit_hash null iff status == escalated.
if [ "$status" = "escalated" ] && [ -n "$commit_hash" ]; then
  printf 'compose-envelope: commit_hash must be empty when status=escalated\n' >&2
  exit 1
fi

# Convert empty strings for nullable fields into JSON nulls via --arg then `| if == "" then null`.
# jq handles escaping of all string inputs safely.

files_arr_json=$(jq -Rs 'split("\n") | map(select(length > 0))' < "$files_changed_file")

envelope=$(jq -n \
  --arg issue              "$issue_s" \
  --arg root_cause         "$root_cause_s" \
  --arg fix_summary        "$fix_summary_s" \
  --argjson files_changed  "$files_arr_json" \
  --arg commit_hash        "$commit_hash" \
  --arg feature_spec_path  "$feature_spec_path" \
  --arg project_name       "${project_name:-}" \
  --arg resolves_issue     "$resolves_issue" \
  --arg status             "$status" \
  '{
    issue:              $issue,
    root_cause:         $root_cause,
    fix_summary:        $fix_summary,
    files_changed:      $files_changed,
    commit_hash:        (if $commit_hash       == "" then null else $commit_hash       end),
    feature_spec_path:  (if $feature_spec_path == "" then null else $feature_spec_path end),
    project_name:       (if $project_name      == "" then null else $project_name      end),
    resolves_issue:     (if $resolves_issue    == "" then null else $resolves_issue    end),
    status:             $status
  }')

# Final FR-001 invariant: required non-null fields must be non-empty after strip.
for f in issue root_cause fix_summary; do
  v=$(printf '%s' "$envelope" | jq -r --arg k "$f" '.[$k]')
  if [ -z "$v" ]; then
    printf 'compose-envelope: required field %s became empty (credential-leak strip left it blank?)\n' "$f" >&2
    exit 1
  fi
done

printf '%s\n' "$envelope"
exit 0
