#!/usr/bin/env bash
# auto-flip-on-merge.sh — atomic flip of every roadmap item in a PRD's derived_from: list
# from `state: distilled|specced` → `state: shipped` (+ `status: shipped`, + `pr:`,
# + `shipped_date:`) upon confirmed PR merge.
#
# This helper is a verbatim extraction of Step 4b.5 from
# plugin-kiln/skills/kiln-build-prd/SKILL.md. The extraction is mechanical — observable
# behavior (diagnostic line, exit codes, frontmatter mutations) is byte-for-byte
# identical to the pre-extraction inline block. NFR-002 (zero-behavior-change) is the
# acceptance gate; the regression fixture under
# plugin-kiln/tests/auto-flip-on-merge-fixture/ proves byte-identity vs commit 22a91b10.
#
# Spec: specs/merge-pr-and-sc-grep-guidance/spec.md (FR-008, FR-009, NFR-002).
# Contract: specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md §A.1, §A.2.
#
# Usage:
#   bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh <pr-number> <prd-path>
#
# Positional arguments:
#   $1  PR_NUMBER  — bare numeric (e.g. "189"). Leading "#" is tolerated and stripped.
#   $2  PRD_PATH   — repo-relative path to the merged PRD's PRD.md file.
#
# Output (stdout): exactly ONE diagnostic line per contract §A.2 (byte-identical to
#                  Step 4b.5's pre-extraction emission).
# Output (stderr): warnings about missing entries; does not abort.
# Exit: 0 on success (including skipped paths); non-zero only on usage errors.

# --- Argument parsing ---------------------------------------------------------
PR_NUMBER="${1:-}"
PRD_PATH="${2:-}"
if [ -z "$PR_NUMBER" ] || [ -z "$PRD_PATH" ]; then
  echo "Usage: $0 <pr-number> <prd-path>" >&2
  exit 2
fi
# Strip optional leading '#' from PR_NUMBER (contract §A.1).
PR_NUMBER="${PR_NUMBER#\#}"
if [ ! -f "$PRD_PATH" ]; then
  echo "auto-flip-on-merge: PRD path not found: $PRD_PATH" >&2
  exit 2
fi

# --- read_derived_from helper (verbatim from Step 4b, kiln-build-prd/SKILL.md) -
# Spec: prd-derived-from-frontmatter (FR-004, FR-005).
read_derived_from() {
  local prd="$1"
  [ -f "$prd" ] || { return 0; }
  awk '
    BEGIN { state = "before"; emit = 0 }
    # Close on the second --- (end of frontmatter block)
    state == "inside" && /^---[[:space:]]*$/ { exit 0 }
    # Open on the first --- (must be the first non-empty line)
    state == "before" && /^---[[:space:]]*$/ { state = "inside"; next }
    # Bail if the first non-empty line is not ---
    state == "before" && NF > 0 { exit 0 }
    # Inside the block
    state == "inside" {
      # Start of derived_from key (inline empty list or block-sequence header)
      if ($0 ~ /^derived_from:[[:space:]]*(\[\])?[[:space:]]*$/) {
        emit = 1
        next
      }
      # Any other top-level key closes the emit window
      if (emit == 1 && $0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        emit = 0
        next
      }
      # Block-sequence entry under derived_from
      if (emit == 1 && $0 ~ /^[[:space:]]+-[[:space:]]+/) {
        # Strip the leading "  - " and any trailing CR/whitespace
        sub(/^[[:space:]]+-[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        gsub(/\r/, "", $0)
        if (length($0) > 0) print $0
      }
    }
  ' "$prd"
}

# Sibling-script lookup so the helper resolves update-item-state.sh from its own
# directory, regardless of caller CWD. Under canonical invocation (CWD=repo-root,
# `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh ...`) this resolves to
# the same relative path as the pre-extraction inline block. Under fixture
# invocation (CWD=$TMP, absolute helper path) it resolves to the real script.
HELPER_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Verbatim Step 4b.5 logic -------------------------------------------------

# FR-003 — gate on PR merge state (cached once per pipeline run; see R-1 mitigation).
PR_STATE_JSON="$(gh pr view "$PR_NUMBER" --json state,mergedAt 2>/dev/null || echo '{}')"
PR_STATE="$(echo "$PR_STATE_JSON" | jq -r '.state // "unknown"')"
if [ "$PR_STATE" != "MERGED" ]; then
  # Edge case: gh unavailable → PR_STATE="unknown" → still emits skipped, never aborts the pipeline.
  REASON="pr-not-merged"
  if [ "$PR_STATE" = "unknown" ]; then REASON="gh-unavailable"; fi
  echo "step4b-auto-flip: pr-state=${PR_STATE} auto-flip=skipped items=0 patched=0 already_shipped=0 reason=${REASON}"
  return 0 2>/dev/null || exit 0
fi

# FR-001 — read derived_from list (reuse Step 4b's read_derived_from helper; see Module E in contracts).
ITEMS=()
MISSING_ENTRIES=()
while IFS= read -r entry; do
  case "$entry" in
    .kiln/roadmap/items/*.md)
      if [ -f "$entry" ]; then
        ITEMS+=("$entry")
      else
        MISSING_ENTRIES+=("$entry")
      fi
      ;;
  esac
done < <(read_derived_from "$PRD_PATH")

# Edge case: no derived_from entries at all → diagnostic with reason=no-derived-from, no-op.
if [ "${#ITEMS[@]}" -eq 0 ] && [ "${#MISSING_ENTRIES[@]}" -eq 0 ]; then
  echo "step4b-auto-flip: pr-state=MERGED auto-flip=skipped items=0 patched=0 already_shipped=0 reason=no-derived-from"
  return 0 2>/dev/null || exit 0
fi

PATCHED=0
ALREADY_SHIPPED=0
TODAY="$(date -u +%Y-%m-%d)"

# FR-001/FR-002/FR-004 — per-item atomic flip with idempotency guard.
for item in "${ITEMS[@]}"; do
  # FR-004 — idempotency: skip if `pr: <PR_NUMBER>` already present (with optional leading '#').
  if grep -qE "^pr:[[:space:]]*#?${PR_NUMBER}\b" "$item"; then
    ALREADY_SHIPPED=$((ALREADY_SHIPPED + 1))
    continue
  fi

  # FR-002 — atomic state+status rewrite via the extended --status flag.
  bash "$HELPER_DIR/update-item-state.sh" "$item" shipped --status shipped >/dev/null

  # FR-001 — patch frontmatter: insert pr: + shipped_date: if absent. ONE awk pass + mv (atomic).
  patch_pr_and_date() {
    local _item="$1" _pr="$2" _today="$3"
    local _tmp
    _tmp="$(mktemp "${_item}.XXXXXX.tmp")"
    awk -v pr="$_pr" -v today="$_today" '
      BEGIN { fm = 0; saw_pr = 0; saw_date = 0; closed = 0 }
      /^---[[:space:]]*$/ {
        fm++
        # FR-004 — on closing fence: insert pr: + shipped_date: if not seen, BEFORE printing the fence.
        if (fm == 2 && closed == 0) {
          if (saw_pr == 0)   { print "pr: " pr }
          if (saw_date == 0) { print "shipped_date: " today }
          closed = 1
        }
        print
        next
      }
      fm == 1 && /^pr:[[:space:]]*/         { saw_pr = 1;   print; next }
      fm == 1 && /^shipped_date:[[:space:]]*/ { saw_date = 1; print; next }
      { print }
    ' "$_item" > "$_tmp"
    mv "$_tmp" "$_item"
  }
  patch_pr_and_date "$item" "$PR_NUMBER" "$TODAY"

  PATCHED=$((PATCHED + 1))
done

# FR-001 — diagnostic line, byte-exact per contract §A.2.
echo "step4b-auto-flip: pr-state=MERGED auto-flip=success items=${#ITEMS[@]} patched=${PATCHED} already_shipped=${ALREADY_SHIPPED} reason="
