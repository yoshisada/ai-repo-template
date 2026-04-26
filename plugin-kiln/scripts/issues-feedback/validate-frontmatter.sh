#!/usr/bin/env bash
# validate-frontmatter.sh — research-block validator for issue and feedback
# frontmatter files. Wraps parse-research-block.sh + validate-research-block.sh
# so the schema check is identical across the four intake surfaces (item /
# issue / feedback / PRD).
#
# Spec:     specs/research-first-completion/spec.md (FR-002)
# Plan:     specs/research-first-completion/plan.md (Decision 3 — outcome (b),
#           no pre-existing validator → create one new wrapper for both
#           surfaces).
# Contract: specs/research-first-completion/contracts/interfaces.md §2.
#
# Usage:
#   validate-frontmatter.sh <file-path>
#
# Stdout: {"ok": bool, "errors": [...], "warnings": [...]} byte-stable.
# Exit:   0 always (validation result is in JSON, not exit code) — matches
#         validate-item-frontmatter.sh precedent.
#
# Backward compat (NFR-001): files without research-block keys produce
# { ok: true, errors: [], warnings: [] }. The wrapper does NOT validate any
# other frontmatter shape — it is research-block-only.

set -u

FILE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/../research/parse-research-block.sh"
HELPER="$SCRIPT_DIR/../research/validate-research-block.sh"

emit() {
  printf '%s\n' "$1"
}

if [ -z "$FILE" ]; then
  emit '{"ok":false,"errors":["missing path argument"],"warnings":[]}'
  exit 0
fi

if [ ! -f "$FILE" ]; then
  emit '{"ok":false,"errors":["file not found: '"$FILE"'"],"warnings":[]}'
  exit 0
fi

if [ ! -x "$PARSER" ] || [ ! -x "$HELPER" ]; then
  emit '{"ok":false,"errors":["research-block parser/helper missing"],"warnings":[]}'
  exit 0
fi

RB_STDERR="$(mktemp)"
RB_JSON="$(bash "$PARSER" "$FILE" 2>"$RB_STDERR")"
RB_RC=$?

if [ "$RB_RC" -ne 0 ]; then
  PARSE_ERR="$(grep -oE 'parse error: .*' "$RB_STDERR" | head -1 | sed 's/^parse error: //')"
  [ -z "$PARSE_ERR" ] && PARSE_ERR="research-block parse failed (rc=$RB_RC)"
  rm -f "$RB_STDERR"
  printf '{"ok":false,"errors":["%s"],"warnings":[]}\n' \
    "$(printf '%s' "$PARSE_ERR" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  exit 0
fi

rm -f "$RB_STDERR"

if [ -z "$RB_JSON" ]; then
  emit '{"ok":true,"errors":[],"warnings":[]}'
  exit 0
fi

bash "$HELPER" "$RB_JSON" 2>/dev/null
