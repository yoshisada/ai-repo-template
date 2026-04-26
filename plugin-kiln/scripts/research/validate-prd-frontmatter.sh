#!/usr/bin/env bash
# validate-prd-frontmatter.sh — research-block validator for PRD frontmatter.
# Thin wrapper around parse-prd-frontmatter.sh + validate-research-block.sh
# so the schema check is identical across the four intake surfaces (item /
# issue / feedback / PRD).
#
# Spec:     specs/research-first-completion/spec.md (FR-004)
# Plan:     specs/research-first-completion/plan.md (Decision 6 — calls the
#           shared helper, no new top-level PRD validator script).
# Contract: specs/research-first-completion/contracts/interfaces.md §2 + §3.
#
# Usage:
#   validate-prd-frontmatter.sh <prd-path>
#
# Stdout: {"ok": bool, "errors": [...], "warnings": [...]} byte-stable.
# Exit:   0 always (validation result is in JSON, not exit code).
#
# Backward compat (NFR-001 + NFR-009): a PRD without research-block keys
# produces { ok: true, errors: [], warnings: [] }. parse-prd-frontmatter.sh's
# existing exit codes are preserved — when the parser bails (loud-fail per
# NFR-007), the wrapper surfaces the bail message as a validation error.

set -u

PRD="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/../../../plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"
HELPER="$SCRIPT_DIR/validate-research-block.sh"

emit() {
  printf '%s\n' "$1"
}

if [ -z "$PRD" ]; then
  emit '{"ok":false,"errors":["missing prd-path argument"],"warnings":[]}'
  exit 0
fi

if [ ! -f "$PRD" ]; then
  emit '{"ok":false,"errors":["prd file not found: '"$PRD"'"],"warnings":[]}'
  exit 0
fi

if [ ! -x "$PARSER" ] || [ ! -x "$HELPER" ]; then
  emit '{"ok":false,"errors":["parser/helper missing"],"warnings":[]}'
  exit 0
fi

PRD_STDERR="$(mktemp)"
PRD_JSON="$(bash "$PARSER" "$PRD" 2>"$PRD_STDERR")"
PRD_RC=$?

if [ "$PRD_RC" -ne 0 ]; then
  PARSE_ERR="$(grep -oE 'parse error: .*' "$PRD_STDERR" | head -1 | sed 's/^parse error: //')"
  if [ -z "$PARSE_ERR" ]; then
    PARSE_ERR="$(grep -oE 'output_quality-axis-missing-rubric: .*' "$PRD_STDERR" | head -1)"
  fi
  [ -z "$PARSE_ERR" ] && PARSE_ERR="prd-frontmatter parse failed (rc=$PRD_RC)"
  rm -f "$PRD_STDERR"
  printf '{"ok":false,"errors":["%s"],"warnings":[]}\n' \
    "$(printf '%s' "$PARSE_ERR" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  exit 0
fi

rm -f "$PRD_STDERR"

if [ -z "$PRD_JSON" ]; then
  emit '{"ok":true,"errors":[],"warnings":[]}'
  exit 0
fi

bash "$HELPER" "$PRD_JSON" 2>/dev/null
