#!/usr/bin/env bash
# invoke-promote-handoff.sh — Emit a per-entry hand-off envelope stream for
# the distill gate's "promote these first?" prompt (confirm-never-silent,
# per-entry accept/skip — FR-005 / Clarification 4).
#
# This script is INTENTIONALLY pure plumbing: it does NOT drive the
# promotion itself. The call-site pattern (per contract §1 "Call Sites") is:
#
#   1. Skill surfaces a per-entry prompt to the user, using the envelope
#      stream this script emits as the canonical list of candidates.
#   2. For each accepted entry, the skill invokes /kiln:kiln-roadmap
#      --promote <path> via the Skill tool.
#   3. After promotions complete, the skill re-runs detect-un-promoted.sh
#      to re-classify and re-bundles the newly-promoted items.
#
# That lets the handoff UX live in the Skill (where it can use Skill tool
# dispatch for confirm-never-silent) while the enumeration semantics stay
# in a single scriptable contract surface.
#
# FR-005 / workflow-governance FR-005: per-entry accept/skip, not a global
# confirm. The envelope stream is ORDER-PRESERVING so the Skill iterates
# in caller-supplied order.
#
# Contract: specs/workflow-governance/contracts/interfaces.md §1
#
# Usage:
#   bash invoke-promote-handoff.sh <source-path> [<source-path> ...]
#
# Stdout (NDJSON — one envelope per input, in input order):
#   {"path":"<path>","title":"<title-from-frontmatter>","prompt":"[accept|skip] <path> — <title>"}
#
# Exit codes:
#   0 success
#   2 usage error (no arguments)
#
# Note: the stdout schema differs intentionally from the original contract
# draft (which had the script itself write accept/skip decisions). The
# decision sink was moved into the Skill layer so confirm-never-silent is
# honored via Skill tool invocation. The envelope shape here is a superset
# of the original: it includes `prompt` (the render string) so the Skill
# can surface it verbatim. "skip" / "promote" decisions are emitted by the
# Skill itself after the user answers.
set -euo pipefail
LC_ALL=C
export LC_ALL

if [[ $# -eq 0 ]]; then
  echo "invoke-promote-handoff: usage: invoke-promote-handoff.sh <source-path> [<source-path> ...]" >&2
  exit 2
fi

# FR-005: extract the title from the source's frontmatter for a user-
# friendly prompt.
read_fm_title() {
  local file=$1
  awk '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 && /^title:[[:space:]]*/ {
      s=$0; sub(/^title:[[:space:]]*/, "", s)
      sub(/[[:space:]]+$/, "", s)
      gsub(/^"|"$/, "", s); gsub(/^'\''|'\''$/, "", s)
      print s; exit
    }
    fm >= 2 { exit }
  ' "$file"
}

for input in "$@"; do
  title=""
  if [[ -f "$input" ]]; then
    title=$(read_fm_title "$input")
  fi
  [[ -n "$title" ]] || title="(no title)"
  # jq-safe JSON emission — escape backslashes + quotes in both fields.
  p_esc=${input//\\/\\\\}; p_esc=${p_esc//\"/\\\"}
  t_esc=${title//\\/\\\\}; t_esc=${t_esc//\"/\\\"}
  prompt="[accept|skip] $input — $title"
  pr_esc=${prompt//\\/\\\\}; pr_esc=${pr_esc//\"/\\\"}
  printf '{"path":"%s","title":"%s","prompt":"%s"}\n' "$p_esc" "$t_esc" "$pr_esc"
done
