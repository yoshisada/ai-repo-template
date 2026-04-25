#!/usr/bin/env bash
# render-workflow.sh — Render a wheel workflow JSON to markdown with embedded Mermaid.
#
# Works on any wheel workflow JSON — runnable workflows OR conceptual
# feedback-loop JSON that carries a top-level `_meta:` extension. Walks
# `steps[]` + `context_from:` edges to emit a flowchart, plus per-step
# prose sections drawn from `_meta.doc` (if present) or the step's
# command/instruction body.
#
# Usage:
#   render-workflow.sh <input.json> [<output.md>]
#
# Defaults:
#   <output.md> = ${CLAUDE_PROJECT_DIR}/docs/feedback-loop/<basename>.md
#
# Portability:
#   - Repo root via ${CLAUDE_PROJECT_DIR} with script-relative fallback.
#   - Requires jq.

set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$REPO_ROOT" ]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
fi

INPUT="${1:-}"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "usage: render-workflow.sh <input.json> [<output.md>]" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq required" >&2
  exit 2
fi

BASENAME="$(basename "$INPUT" .json)"
OUTPUT="${2:-$REPO_ROOT/docs/feedback-loop/$BASENAME.md}"
mkdir -p "$(dirname "$OUTPUT")"

# Repo-relative path for the "do not edit" banner
INPUT_REL="${INPUT#$REPO_ROOT/}"

NAME=$(jq -r '.name // "(unnamed)"' "$INPUT")
DESCRIPTION=$(jq -r '.description // ""' "$INPUT")
META_KIND=$(jq -r '._meta.kind // empty' "$INPUT")
META_STATUS=$(jq -r '._meta.status // empty' "$INPUT")
META_OWNER=$(jq -r '._meta.owner // empty' "$INPUT")

{
  printf '# %s\n\n' "$NAME"
  printf '> _Generated from `%s` — do not edit by hand. Regenerate via `plugin-wheel/scripts/render/render-workflow.sh`._\n\n' "$INPUT_REL"

  if [ -n "$DESCRIPTION" ]; then
    printf '%s\n\n' "$DESCRIPTION"
  fi

  # --- _meta block (if any field present) ---------------------------------
  if [ -n "$META_KIND" ] || [ -n "$META_STATUS" ] || [ -n "$META_OWNER" ]; then
    printf '## Metadata\n\n'
    printf '| Field | Value |\n|---|---|\n'
    [ -n "$META_KIND" ]   && printf '| kind | `%s` |\n' "$META_KIND"
    [ -n "$META_STATUS" ] && printf '| status | `%s` |\n' "$META_STATUS"
    [ -n "$META_OWNER" ]  && printf '| owner | %s |\n' "$META_OWNER"

    METRICS_KEYS=$(jq -r '._meta.metrics // {} | keys[]?' "$INPUT" 2>/dev/null)
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      v=$(jq -r --arg k "$k" '._meta.metrics[$k]' "$INPUT")
      printf '| metrics.%s | %s |\n' "$k" "$v"
    done <<< "$METRICS_KEYS"

    AP_COUNT=$(jq -r '._meta.anti_patterns // [] | length' "$INPUT")
    if [ "$AP_COUNT" -gt 0 ]; then
      printf '\n### Anti-patterns\n\n'
      jq -r '._meta.anti_patterns[] | "- \(.)"' "$INPUT"
      printf '\n'
    fi

    RL_COUNT=$(jq -r '._meta.related_loops // [] | length' "$INPUT")
    if [ "$RL_COUNT" -gt 0 ]; then
      printf '\n### Related loops\n\n'
      jq -r '._meta.related_loops[] | "- `\(.)`"' "$INPUT"
      printf '\n'
    fi

    printf '\n'
  fi

  # --- Mermaid diagram ----------------------------------------------------
  printf '## Flow\n\n'
  printf '```mermaid\nflowchart TD\n'
  jq -r '.steps[] | "  \(.id)[\"\(.id)\\n(\(.type))\"]"' "$INPUT"

  HAS_EDGES=$(jq -r '[.steps[] | .context_from // [] | length] | add // 0' "$INPUT")
  if [ "$HAS_EDGES" -gt 0 ]; then
    jq -r '.steps[] as $s | $s.context_from // [] | .[] | "  \(.) --> \($s.id)"' "$INPUT"
  else
    jq -r '.steps as $s | range(0; ($s | length) - 1) | "  \($s[.].id) --> \($s[. + 1].id)"' "$INPUT"
  fi
  printf '```\n\n'

  # --- Per-step prose sections --------------------------------------------
  printf '## Steps\n\n'
  N_STEPS=$(jq -r '.steps | length' "$INPUT")
  for i in $(seq 0 $((N_STEPS - 1))); do
    STEP_ID=$(jq -r ".steps[$i].id" "$INPUT")
    STEP_TYPE=$(jq -r ".steps[$i].type" "$INPUT")
    STEP_DOC=$(jq -r ".steps[$i]._meta.doc // empty" "$INPUT")
    STEP_ACTOR=$(jq -r ".steps[$i]._meta.actor // empty" "$INPUT")

    printf '### %s\n\n' "$STEP_ID"
    printf '**Type:** `%s`' "$STEP_TYPE"
    [ -n "$STEP_ACTOR" ] && printf ' &nbsp; **Actor:** `%s`' "$STEP_ACTOR"
    printf '\n\n'

    if [ -n "$STEP_DOC" ]; then
      printf '%s\n\n' "$STEP_DOC"
    else
      if [ "$STEP_TYPE" = "command" ]; then
        CMD=$(jq -r ".steps[$i].command // empty" "$INPUT" | head -c 200)
        if [ -n "$CMD" ]; then
          printf '```bash\n%s\n```\n\n' "$CMD"
        fi
      elif [ "$STEP_TYPE" = "agent" ]; then
        FIRST_LINE=$(jq -r ".steps[$i].instruction // empty" "$INPUT" | head -1)
        if [ -n "$FIRST_LINE" ]; then
          printf '_%s_\n\n' "$FIRST_LINE"
        fi
      fi
    fi
  done
} > "$OUTPUT"

echo "rendered: $OUTPUT"
