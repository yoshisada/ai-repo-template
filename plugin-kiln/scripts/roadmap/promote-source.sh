#!/usr/bin/env bash
# promote-source.sh — Promote a raw .kiln/issues/*.md or .kiln/feedback/*.md
# source into a structured .kiln/roadmap/items/*.md roadmap item with a
# byte-preserving update of the source file's body.
#
# FR-006 / workflow-governance FR-006: first-class --promote path on
# /kiln:kiln-roadmap — reads source, writes new item with
# `promoted_from: <source>`, updates source frontmatter to
# `status: promoted` + `roadmap_item: <new-path>`.
#
# NFR-003 / workflow-governance NFR-003: the source body (everything after
# the closing `---`) is byte-identical to pre-invocation. Only the
# frontmatter block may change.
#
# Contract: specs/workflow-governance/contracts/interfaces.md §2
#
# Usage:
#   bash promote-source.sh \
#     --source <path> \
#     --kind <feature|goal|research|constraint|non-goal|milestone|critique> \
#     --blast-radius <isolated|feature|cross-cutting|infra> \
#     --review-cost <trivial|moderate|careful|expert> \
#     --context-cost <free-text> \
#     --phase <phase-name> \
#     --slug <slug> \
#     [--title <title>] \
#     [--status <kind-specific-status>]
#
# Stdout (exit 0): {"new_item_path":"...","source_path":"..."}
#
# Exit codes (per contract §2):
#   0 success
#   2 usage error
#   3 source path does not exist
#   4 source has no frontmatter (cannot write back-reference)
#   5 source already `status: promoted` (idempotency guard)
#   6 target item file already exists

set -euo pipefail
LC_ALL=C   # deterministic sort / regex byte semantics
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "promote-source: $1" >&2; exit "${2:-2}"; }
err_exit() { echo "promote-source: $1" >&2; exit "$2"; }

SOURCE="" KIND="" BLAST="" REVIEW="" CONTEXT="" PHASE="" SLUG="" TITLE="" STATUS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)        SOURCE="$2"; shift 2;;
    --kind)          KIND="$2";   shift 2;;
    --blast-radius)  BLAST="$2";  shift 2;;
    --review-cost)   REVIEW="$2"; shift 2;;
    --context-cost)  CONTEXT="$2"; shift 2;;
    --phase)         PHASE="$2";  shift 2;;
    --slug)          SLUG="$2";   shift 2;;
    --title)         TITLE="$2";  shift 2;;
    --status)        STATUS="$2"; shift 2;;
    *) die "unknown flag: $1" 2;;
  esac
done

# FR-006: required flags must all be present.
for v in SOURCE KIND BLAST REVIEW CONTEXT PHASE SLUG; do
  if [[ -z "${!v}" ]]; then
    die "missing required flag: --${v,,}" 2
  fi
done

# FR-006: validate kind against the 7-kind enum.
case "$KIND" in
  feature|goal|research|constraint|non-goal|milestone|critique) ;;
  *) die "invalid --kind: $KIND (allowed: feature|goal|research|constraint|non-goal|milestone|critique)" 2;;
esac

# FR-006: validate blast_radius and review_cost against the structured-roadmap
# enums (matches validate-item-frontmatter.sh §1.3).
case "$BLAST" in
  isolated|feature|cross-cutting|infra) ;;
  *) die "invalid --blast-radius: $BLAST (allowed: isolated|feature|cross-cutting|infra)" 2;;
esac
case "$REVIEW" in
  trivial|moderate|careful|expert) ;;
  *) die "invalid --review-cost: $REVIEW (allowed: trivial|moderate|careful|expert)" 2;;
esac

# FR-006: source existence guard (exit 3).
if [[ ! -f "$SOURCE" ]]; then
  err_exit "source path does not exist: $SOURCE" 3
fi

# FR-006: detect frontmatter. The source MUST have a frontmatter block
# (opened with `---` on line 1). Otherwise exit 4.
first_line="$(head -n 1 "$SOURCE" 2>/dev/null || true)"
if [[ "$first_line" != "---" ]]; then
  err_exit "source has no frontmatter (first line != '---'): $SOURCE" 4
fi

# Parse current status from the source frontmatter (only the frontmatter — do
# NOT consume the body). FR-006 / Acceptance Scenario 5 (idempotency guard).
existing_status="$(awk '
  /^---[[:space:]]*$/ { fm++; next }
  fm == 1 && /^status:[[:space:]]*/ {
    s = $0; sub(/^status:[[:space:]]*/, "", s)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    gsub(/^"|"$/, "", s)
    print s; exit
  }
  fm >= 2 { exit }
' "$SOURCE")"

if [[ "$existing_status" == "promoted" ]]; then
  # Surface the existing roadmap_item back-link if present so the user can
  # navigate directly.
  existing_item="$(awk '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 && /^roadmap_item:[[:space:]]*/ {
      s = $0; sub(/^roadmap_item:[[:space:]]*/, "", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/^"|"$/, "", s)
      print s; exit
    }
    fm >= 2 { exit }
  ' "$SOURCE")"
  echo "promote-source: source is already status: promoted — see ${existing_item:-<unknown>}" >&2
  exit 5
fi

# FR-006: compute new item path. The date prefix uses the source file's
# existing date if its basename already starts with YYYY-MM-DD (promotes
# preserve origin date — matches the "file on 2026-04-24" style); otherwise
# today's UTC date.
source_base="$(basename "$SOURCE" .md)"
if [[ "$source_base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
  DATE_PREFIX="${BASH_REMATCH[1]}"
else
  DATE_PREFIX="$(date -u +%Y-%m-%d)"
fi

ITEMS_DIR=".kiln/roadmap/items"
mkdir -p "$ITEMS_DIR"

ITEM_ID="${DATE_PREFIX}-${SLUG}"
ITEM_PATH="${ITEMS_DIR}/${ITEM_ID}.md"

# FR-006: target-existence guard (exit 6). We do NOT auto-increment a
# counter here — promotion should be explicit; if the target already exists,
# the caller picks a different slug.
if [[ -f "$ITEM_PATH" ]]; then
  err_exit "target item file already exists: $ITEM_PATH" 6
fi

# Derive the title: prefer --title; else the source's first H1 (# Foo);
# else the source frontmatter title; else fall back to the slug.
derive_title() {
  local p="$1"
  local t=""
  t="$(awk '
    /^---[[:space:]]*$/ { fm++; next }
    fm < 2 { next }
    /^#[[:space:]]+/ {
      sub(/^#[[:space:]]+/, ""); print; exit
    }
  ' "$p")"
  if [[ -z "$t" ]]; then
    t="$(awk '
      /^---[[:space:]]*$/ { fm++; next }
      fm == 1 && /^title:[[:space:]]*/ {
        s = $0; sub(/^title:[[:space:]]*/, "", s)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        gsub(/^"|"$/, "", s)
        print s; exit
      }
    ' "$p")"
  fi
  printf '%s' "$t"
}

if [[ -z "$TITLE" ]]; then
  TITLE="$(derive_title "$SOURCE")"
  [[ -n "$TITLE" ]] || TITLE="$SLUG"
fi

# Default status: first status in the kind-specific allowed set. Kept in
# sync with status_for_kind in validate-item-frontmatter.sh.
if [[ -z "$STATUS" ]]; then
  case "$KIND" in
    feature|goal|research|critique) STATUS="open" ;;
    constraint|non-goal)            STATUS="active" ;;
    milestone)                      STATUS="pending" ;;
  esac
fi

# YAML-escape the title (double-quote form). Backslash-escape " and \.
yaml_dq() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# FR-006: compose + write the new item. critique kind requires proof_path
# (validate-item-frontmatter.sh FR-011) — for promote flows the source
# itself is the proof document.
TMP_ITEM="$(mktemp "${ITEM_PATH}.XXXXXX.tmp")"
trap 'rm -f "$TMP_ITEM"' EXIT

{
  printf -- '---\n'
  printf 'id: %s\n' "$ITEM_ID"
  printf 'title: %s\n' "$(yaml_dq "$TITLE")"
  printf 'kind: %s\n' "$KIND"
  printf 'date: %s\n' "$DATE_PREFIX"
  printf 'status: %s\n' "$STATUS"
  printf 'phase: %s\n' "$PHASE"
  printf 'state: planned\n'
  printf 'blast_radius: %s\n' "$BLAST"
  printf 'review_cost: %s\n' "$REVIEW"
  printf 'context_cost: %s\n' "$(yaml_dq "$CONTEXT")"
  printf 'promoted_from: %s\n' "$SOURCE"
  if [[ "$KIND" == "critique" ]]; then
    printf 'proof_path: %s\n' "$SOURCE"
  fi
  printf -- '---\n\n'
  printf '# %s\n\n' "$TITLE"
  printf 'Promoted from [`%s`](%s) on %s.\n\n' "$SOURCE" "$SOURCE" "$DATE_PREFIX"
  printf 'See the source file for the full narrative; this roadmap item carries the structured classification (kind, sizing, phase) required by the distill gate (FR-004 of workflow-governance).\n'
} > "$TMP_ITEM"

mv "$TMP_ITEM" "$ITEM_PATH"
trap - EXIT

# Validate at the final name (validate-item-frontmatter.sh checks basename
# parity, so pre-mv validation against a *.tmp name would always trip the
# id-vs-basename rule). On validation failure we roll back the write so the
# caller sees a clean error instead of a malformed item file.
VALIDATE="$SCRIPT_DIR/validate-item-frontmatter.sh"
if [[ -f "$VALIDATE" ]]; then
  V_JSON="$(bash "$VALIDATE" "$ITEM_PATH" 2>/dev/null || true)"
  V_OK="$(printf '%s' "$V_JSON" | jq -r '.ok' 2>/dev/null || echo false)"
  if [[ "$V_OK" != "true" ]]; then
    echo "promote-source: validation failed for new item — rolling back:" >&2
    printf '%s' "$V_JSON" | jq -r '.errors[]? // empty' >&2 || true
    rm -f "$ITEM_PATH"
    exit 2
  fi
fi

# NFR-003: byte-preserving source update. We rewrite only the frontmatter
# block (the bytes between the first `---\n` and the line that closes the
# frontmatter). Everything after the closing `---` is copied verbatim.
#
# Frontmatter rewrite rules:
#   - Remove any existing `status:` / `roadmap_item:` line (drop).
#   - Append `status: promoted` at the end of the frontmatter block (before
#     the closing `---`).
#   - Append `roadmap_item: <new-path>`.
#   - Leave every other frontmatter line byte-for-byte.
TMP_SOURCE="$(mktemp "${SOURCE}.XXXXXX.tmp")"
trap 'rm -f "$TMP_SOURCE"' EXIT

awk -v newpath="$ITEM_PATH" '
  BEGIN { fm = 0 }
  /^---[[:space:]]*$/ {
    fm++
    if (fm == 2) {
      # Just before closing fence, emit the new back-reference fields.
      print "status: promoted"
      print "roadmap_item: " newpath
    }
    print
    next
  }
  fm == 1 {
    if ($0 ~ /^status:[[:space:]]*/ || $0 ~ /^roadmap_item:[[:space:]]*/) next
    print
    next
  }
  { print }
' "$SOURCE" > "$TMP_SOURCE"

# Byte-preservation guard: compare the body (everything after the SECOND
# `---`) in both files — MUST be identical. If not, abort and preserve
# original.
extract_body() {
  awk '
    /^---[[:space:]]*$/ { fm++; if (fm == 2) { inbody = 1; next } }
    inbody == 1 { print }
  ' "$1"
}

old_body_hash="$(extract_body "$SOURCE" | shasum -a 256 | awk '{print $1}' 2>/dev/null || true)"
new_body_hash="$(extract_body "$TMP_SOURCE" | shasum -a 256 | awk '{print $1}' 2>/dev/null || true)"

if [[ -z "$old_body_hash" ]] || [[ "$old_body_hash" != "$new_body_hash" ]]; then
  echo "promote-source: NFR-003 byte-preservation check failed (body hash drift) — rolling back" >&2
  # Roll back the new item file too — no partial state.
  rm -f "$ITEM_PATH" "$TMP_SOURCE"
  trap - EXIT
  exit 2
fi

mv "$TMP_SOURCE" "$SOURCE"
trap - EXIT

# Success envelope (contract §2 stdout schema).
printf '{"new_item_path":"%s","source_path":"%s"}\n' "$ITEM_PATH" "$SOURCE"
