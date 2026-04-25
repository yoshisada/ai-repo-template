#!/usr/bin/env bash
# FR-011: Compute a stable pi-hash for one PI block.
# Contract: specs/workflow-governance/contracts/interfaces.md Module 3 §compute-pi-hash.sh
# Algorithm (Clarification 7): sha256(issue# || "|" || target_file || "|" || target_anchor || "|" || proposed_diff)
# truncated to first 12 hex characters.
#
# Shared convention (contracts/interfaces.md §Shared conventions): fall back to
# `shasum -a 256` when `sha256sum` is unavailable (macOS).

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: compute-pi-hash.sh --issue-number <N> --target-file <path> --target-anchor <anchor> --proposed-diff <text>
USAGE
  exit 2
}

ISSUE_NUMBER=""
TARGET_FILE=""
TARGET_ANCHOR=""
PROPOSED_DIFF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number)   ISSUE_NUMBER="${2:-}"; shift 2 ;;
    --target-file)    TARGET_FILE="${2:-}"; shift 2 ;;
    --target-anchor)  TARGET_ANCHOR="${2:-}"; shift 2 ;;
    --proposed-diff)  PROPOSED_DIFF="${2:-}"; shift 2 ;;
    -h|--help)        usage ;;
    *)                echo "compute-pi-hash.sh: unknown flag: $1" >&2; usage ;;
  esac
done

# All four fields are required — empty strings are permitted but absent flags are not.
[[ -z "${ISSUE_NUMBER}${TARGET_FILE}${TARGET_ANCHOR}${PROPOSED_DIFF}" ]] && usage
[[ -z "$ISSUE_NUMBER" ]] && { echo "compute-pi-hash.sh: --issue-number required" >&2; exit 2; }
[[ -z "$TARGET_FILE" ]]  && { echo "compute-pi-hash.sh: --target-file required" >&2; exit 2; }
[[ -z "$TARGET_ANCHOR" ]] && { echo "compute-pi-hash.sh: --target-anchor required" >&2; exit 2; }

# Pick the right sha256 tool. macOS ships `shasum -a 256`; Linux coreutils ships `sha256sum`.
if command -v sha256sum >/dev/null 2>&1; then
  SHA256_CMD="sha256sum"
else
  SHA256_CMD="shasum -a 256"
fi

# Compose the canonical input with literal "|" separators. Use printf %s to avoid
# trailing newlines that would perturb the hash.
INPUT=$(printf '%s|%s|%s|%s' "$ISSUE_NUMBER" "$TARGET_FILE" "$TARGET_ANCHOR" "$PROPOSED_DIFF")

# First 12 hex chars of the sha256.
HASH=$(printf '%s' "$INPUT" | $SHA256_CMD | awk '{print substr($1, 1, 12)}')
printf '%s\n' "$HASH"
