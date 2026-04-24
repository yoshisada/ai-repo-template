#!/usr/bin/env bash
# FR-010 / SC-004: Assemble the final pi-apply report from NDJSON records on stdin.
# Contract: specs/workflow-governance/contracts/interfaces.md Module 3 §emit-report.sh
#
# Writes to .kiln/logs/pi-apply-<ISO-8601>.md. Section order is deterministic:
#   1. Actionable PIs
#   2. Already-Applied PIs
#   3. Stale PIs (anchor not found)
#   4. Parse Errors
# Empty sections render "(none)" so the schema stays diff-stable.
#
# Records inside each section are sorted by (issue_number ASC, pi_id ASC) under
# LC_ALL=C for byte-identical output across macOS/Linux (SC-004 determinism).

set -euo pipefail

# FR-009: timestamp format is ISO-8601 UTC, seconds precision, per shared convention.
TIMESTAMP="${PI_APPLY_TIMESTAMP_OVERRIDE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

# Read all NDJSON records into memory.
RECORDS=$(cat)

if [[ -z "${RECORDS// /}" ]]; then
  # Empty stream → still emit a stable empty report for the audit trail.
  mkdir -p .kiln/logs
  OUTPUT=".kiln/logs/pi-apply-${TIMESTAMP}.md"
  {
    printf '# PI-Apply Report — %s\n\n' "$TIMESTAMP"
    printf 'Summary: 0 actionable, 0 already-applied, 0 stale, 0 parse errors\n\n'
    printf 'No open retro issues found.\n\n'
    printf '## Actionable PIs\n\n(none)\n\n'
    printf '## Already-Applied PIs\n\n(none)\n\n'
    printf '## Stale PIs (anchor not found)\n\n(none)\n\n'
    printf '## Parse Errors\n\n(none)\n'
  } > "$OUTPUT"
  echo "$OUTPUT"
  exit 0
fi

# Partition records by status (plus parse_error bucket). `printf %s` avoids the
# `echo` builtin's variable `\n`-expansion behavior that would corrupt JSON strings.
ACTIONABLE=$(printf '%s' "$RECORDS" | jq -c 'select(.status == "actionable")'       || true)
APPLIED=$(printf '%s' "$RECORDS"    | jq -c 'select(.status == "already-applied")' || true)
STALE=$(printf '%s' "$RECORDS"      | jq -c 'select(.status == "stale")'           || true)
ERRORS=$(printf '%s' "$RECORDS"     | jq -c 'select(.parse_error != null)'         || true)

# Sort each group deterministically by (issue_number ASC, pi_id ASC).
# Done entirely inside jq so that embedded newlines/quotes/backslashes in string
# fields survive byte-identically — routing through `sort` + @tsv would escape them.
sort_group() {
  local group="$1"
  if [[ -z "$group" ]]; then return 0; fi
  # `slurp` each line into an array, sort, then emit one record per line.
  printf '%s\n' "$group" | jq -sc 'sort_by([.issue_number // 0, .pi_id // ""]) | .[]'
}

ACTIONABLE_SORTED=$(sort_group "$ACTIONABLE")
APPLIED_SORTED=$(sort_group "$APPLIED")
STALE_SORTED=$(sort_group "$STALE")
ERRORS_SORTED=$(sort_group "$ERRORS")

count_records() {
  if [[ -z "$1" ]]; then
    printf '0\n'
  else
    # One record per line; grep -c '.' counts non-empty lines.
    printf '%s\n' "$1" | grep -c '.' || printf '0\n'
  fi
}

N_ACT=$(count_records "$ACTIONABLE_SORTED")
N_APP=$(count_records "$APPLIED_SORTED")
N_STA=$(count_records "$STALE_SORTED")
N_ERR=$(count_records "$ERRORS_SORTED")

# Helpers to render each section.
render_actionable() {
  if [[ -z "$ACTIONABLE_SORTED" ]]; then printf '(none)\n\n'; return; fi
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local issue pi file anchor url why hash diff
    issue=$(printf '%s' "$rec" | jq -r '.issue_number')
    pi=$(printf '%s' "$rec" | jq -r '.pi_id')
    file=$(printf '%s' "$rec" | jq -r '.file')
    anchor=$(printf '%s' "$rec" | jq -r '.anchor')
    url=$(printf '%s' "$rec" | jq -r '.issue_url')
    why=$(printf '%s' "$rec" | jq -r '.why')
    hash=$(printf '%s' "$rec" | jq -r '.pi_hash')
    diff=$(printf '%s' "$rec" | jq -r '.diff')
    printf '### #%s %s — %s @ %s\n' "$issue" "$pi" "$file" "$anchor"
    printf -- '- Source: %s\n' "$url"
    printf -- '- pi-hash: `%s`\n' "$hash"
    printf -- '- Why: %s\n\n' "$why"
    printf '```diff\n%s\n```\n\n' "$diff"
  done <<<"$ACTIONABLE_SORTED"
}

render_simple_section() {
  local group="$1"
  local note="$2"
  if [[ -z "$group" ]]; then printf '(none)\n\n'; return; fi
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local issue pi file anchor url why hash
    issue=$(printf '%s' "$rec" | jq -r '.issue_number')
    pi=$(printf '%s' "$rec" | jq -r '.pi_id')
    file=$(printf '%s' "$rec" | jq -r '.file')
    anchor=$(printf '%s' "$rec" | jq -r '.anchor')
    url=$(printf '%s' "$rec" | jq -r '.issue_url')
    why=$(printf '%s' "$rec" | jq -r '.why // ""')
    hash=$(printf '%s' "$rec" | jq -r '.pi_hash')
    printf '### #%s %s — %s @ %s\n' "$issue" "$pi" "$file" "$anchor"
    printf -- '- Source: %s\n' "$url"
    printf -- '- pi-hash: `%s`\n' "$hash"
    if [[ -n "$why" && "$why" != "null" ]]; then
      printf -- '- Why: %s\n' "$why"
    fi
    printf -- '- Note: %s\n\n' "$note"
  done <<<"$group"
}

render_errors() {
  if [[ -z "$ERRORS_SORTED" ]]; then printf '(none)\n\n'; return; fi
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local issue pi url err lr
    issue=$(printf '%s' "$rec" | jq -r '.issue_number')
    pi=$(printf '%s' "$rec" | jq -r '.pi_id')
    url=$(printf '%s' "$rec" | jq -r '.issue_url // ""')
    err=$(printf '%s' "$rec" | jq -r '.parse_error')
    lr=$(printf '%s' "$rec" | jq -r '.line_range')
    printf '### #%s %s — lines %s\n' "$issue" "$pi" "$lr"
    if [[ -n "$url" && "$url" != "null" ]]; then
      printf -- '- Source: %s\n' "$url"
    fi
    printf -- '- Error: %s\n\n' "$err"
  done <<<"$ERRORS_SORTED"
}

mkdir -p .kiln/logs
OUTPUT=".kiln/logs/pi-apply-${TIMESTAMP}.md"

{
  printf '# PI-Apply Report — %s\n\n' "$TIMESTAMP"
  printf 'Summary: %s actionable, %s already-applied, %s stale, %s parse errors\n\n' "$N_ACT" "$N_APP" "$N_STA" "$N_ERR"

  printf '## Actionable PIs\n\n'
  render_actionable

  printf '## Already-Applied PIs\n\n'
  render_simple_section "$APPLIED_SORTED" "proposed text already present; no diff rendered."

  printf '## Stale PIs (anchor not found)\n\n'
  render_simple_section "$STALE_SORTED" "anchor not found in source tree; manual re-anchor required."

  printf '## Parse Errors\n\n'
  render_errors
} > "$OUTPUT"

echo "$OUTPUT"
