#!/usr/bin/env bash
# FR-011: Render a unified-diff-shaped patch for an actionable PI block.
# Contract: specs/workflow-governance/contracts/interfaces.md Module 3 §render-pi-diff.sh
#
# NOTE (FR-010, propose-don't-apply): this script NEVER writes to the target file.
# It only emits a diff body to stdout.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: render-pi-diff.sh --target-file <path> --target-anchor <anchor> --current <text> --proposed <text>
USAGE
  exit 2
}

TARGET_FILE=""
TARGET_ANCHOR=""
CURRENT=""
PROPOSED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-file)   TARGET_FILE="${2:-}"; shift 2 ;;
    --target-anchor) TARGET_ANCHOR="${2:-}"; shift 2 ;;
    --current)       CURRENT="${2:-}"; shift 2 ;;
    --proposed)      PROPOSED="${2:-}"; shift 2 ;;
    -h|--help)       usage ;;
    *)               echo "render-pi-diff.sh: unknown flag: $1" >&2; usage ;;
  esac
done

[[ -z "$TARGET_FILE" || -z "$TARGET_ANCHOR" ]] && usage

# FR-010: we do not require the target file to exist to emit a diff proposal —
# the audit trail is still valuable. But if the flag tells us to enforce
# readability we surface exit 3. The contract says: "target file unreadable" → 3.
# Here we only fail when the file is present but unreadable; absence is fine
# (the classifier will mark it stale first).
if [[ -e "$TARGET_FILE" && ! -r "$TARGET_FILE" ]]; then
  echo "render-pi-diff.sh: target file exists but is unreadable: $TARGET_FILE" >&2
  exit 3
fi

# Emit the unified-diff body per contract:
#   --- a/<target-file>
#   +++ b/<target-file>
#   @@ <anchor> @@
#   -<current-text>
#   +<proposed-text>
#
# Multi-line CURRENT / PROPOSED values render with a "-" or "+" prefix on each line.
printf -- '--- a/%s\n' "$TARGET_FILE"
printf -- '+++ b/%s\n' "$TARGET_FILE"
printf -- '@@ %s @@\n' "$TARGET_ANCHOR"
if [[ -n "$CURRENT" ]]; then
  # Prefix each line with '-'. The sed '-e' form keeps final newline if present.
  printf '%s\n' "$CURRENT" | sed 's/^/-/'
fi
if [[ -n "$PROPOSED" ]]; then
  printf '%s\n' "$PROPOSED" | sed 's/^/+/'
fi
