#!/usr/bin/env bash
# write-proposal-dispatch.sh
# FR-007, FR-008, FR-009, FR-010, FR-018, FR-019, FR-020
#
# Orchestrator for the write-proposal command sub-step. Reads the reflect
# output, runs validate-reflect-output.sh, verifies `current` text exists
# verbatim in the target file, derives the slug, composes the dispatch
# envelope, and prints it to stdout.
#
# Always exits 0. Always silent on stderr. The envelope is ALWAYS one of:
#   {"action":"skip"}
#   {"action":"write", target, proposal_path, frontmatter, body_sections}
#
# FR-007 / FR-018 / FR-020: on any internal failure (malformed reflect output,
# missing vault root, target not readable, `current` not verbatim, slug empty,
# etc.) this script emits `{"action":"skip"}` and exits 0. No user-visible
# diagnostic. The internal reflect output file remains at its .wheel/outputs/
# location and is not surfaced.

set -u
LC_ALL=C
export LC_ALL

# Locate helper scripts alongside this file so the orchestrator is relocatable
# under the wheel plugin cache — wheel sets ${WORKFLOW_PLUGIN_DIR} but this
# script also works when invoked directly.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REFLECT_OUT=".wheel/outputs/propose-manifest-improvement.json"

CURRENT_TMP=$(mktemp -t prop-manifest-current.XXXXXX) || {
  printf '{"action":"skip"}\n'
  exit 0
}
# FR-007: always clean up the temp file, on any exit.
trap 'rm -f "$CURRENT_TMP"' EXIT

emit_skip() {
  printf '{"action":"skip"}\n'
  exit 0
}

# Ask the validator for a verdict. Validator exits 0 on any outcome.
verdict_json=$(bash "$SCRIPT_DIR/validate-reflect-output.sh" "$REFLECT_OUT" 2>/dev/null || true)
if [ -z "$verdict_json" ]; then
  emit_skip
fi

verdict=$(printf '%s' "$verdict_json" | jq -r '.verdict // empty' 2>/dev/null || echo "")
if [ "$verdict" != "write" ]; then
  emit_skip
fi

target=$(printf '%s' "$verdict_json" | jq -r '.target // ""')
section=$(printf '%s' "$verdict_json" | jq -r '.section // ""')
current=$(printf '%s' "$verdict_json" | jq -r '.current // ""')
proposed=$(printf '%s' "$verdict_json" | jq -r '.proposed // ""')
why=$(printf '%s' "$verdict_json" | jq -r '.why // ""')

if [ -z "$target" ] || [ -z "$current" ] || [ -z "$proposed" ] || [ -z "$why" ]; then
  emit_skip
fi

# FR-005: verify `current` exists verbatim in the target file. This is the
# deterministic exact-patch gate — it runs BEFORE the MCP write.
printf '%s' "$current" > "$CURRENT_TMP"
if ! bash "$SCRIPT_DIR/check-manifest-target-exists.sh" "$target" "$CURRENT_TMP" 2>/dev/null; then
  emit_skip
fi

# FR-010: derive slug from `why`. Empty output -> skip.
slug=$(printf '%s' "$why" | bash "$SCRIPT_DIR/derive-proposal-slug.sh" 2>/dev/null || true)
if [ -z "$slug" ]; then
  emit_skip
fi

date_today=$(date -u +%Y-%m-%d)
proposal_path="@inbox/open/${date_today}-manifest-improvement-${slug}.md"

# FR-008 / FR-009: compose the full write envelope.
jq -n \
  --arg target "$target" \
  --arg section "$section" \
  --arg current "$current" \
  --arg proposed "$proposed" \
  --arg why "$why" \
  --arg proposal_path "$proposal_path" \
  --arg date "$date_today" \
  '{
    action: "write",
    target: $target,
    proposal_path: $proposal_path,
    frontmatter: { type: "proposal", target: $target, date: $date },
    body_sections: {
      target_line: $target,
      section: $section,
      current: $current,
      proposed: $proposed,
      why: $why
    }
  }'
exit 0
