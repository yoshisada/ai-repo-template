#!/usr/bin/env bash
# resolve.sh — Agent resolution primitive (FR-A3, simplified 2026-04-25)
#
# Accepts <path-or-name> and emits a single-line JSON spec on stdout:
#   { subagent_type, system_prompt_path, tools, source, canonical_path, model_default }
#
# Input forms:
#   (a) absolute path           — /abs/path/to/<name>.md
#   (b) repo-relative path      — plugin-<name>/agents/<role>.md
#   (c) plugin-prefixed name    — <plugin>:<role> (e.g. kiln:debugger) — passthrough
#   (d) bare name               — <role> — passthrough as legacy back-compat (source: unknown)
#
# Plugin-prefixed names are the canonical way to reference agents post-FR-A1-reversal
# (2026-04-25). The harness discovers agents via filesystem scan at session start and
# registers them as <plugin>:<role>. This resolver is plugin-agnostic — it does NOT
# maintain a registry of every plugin's agents (the prior plugin-wheel/scripts/agents/
# registry.json was a vision violation and was removed alongside this simplification).
#
# Exit: 0 on success (all forms), 1 on empty input or path-form file-not-found.
# Stderr: loud diagnostic on exit 1 — NEVER silent.

set -euo pipefail

die() {
  echo "resolve.sh: $*" >&2
  exit 1
}

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  die "empty input — usage: resolve.sh <path-or-name>"
fi

emit_json() {
  local subagent_type="$1" sys_path="$2" source="$3" canonical="$4" model_default="$5"
  local tools_json="$6"
  jq -cn \
    --arg st "$subagent_type" \
    --arg sp "$sys_path" \
    --arg src "$source" \
    --arg cp "$canonical" \
    --arg md "$model_default" \
    --argjson tools "$tools_json" \
    '{subagent_type: $st, system_prompt_path: $sp, tools: $tools, source: $src, canonical_path: $cp, model_default: (if $md == "" or $md == "null" then null else $md end)}'
}

is_path_form() {
  case "$1" in
    /*|*/*|*.md) return 0 ;;
    *)           return 1 ;;
  esac
}

if is_path_form "$INPUT"; then
  # Path form (a/b). Locate the agent .md file.
  if [[ "$INPUT" = /* ]]; then
    candidate="$INPUT"
  elif [[ -f "$INPUT" ]]; then
    candidate="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
  elif [[ -z "${WORKFLOW_PLUGIN_DIR:-}" ]]; then
    die "WORKFLOW_PLUGIN_DIR unset and repo-relative path '$INPUT' not found from CWD"
  else
    # Anchor under WORKFLOW_PLUGIN_DIR's parent (consumer install layout)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PLUGIN_ROOT="${WORKFLOW_PLUGIN_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
    parent_root="$(cd "${PLUGIN_ROOT}/.." && pwd)"
    candidate="${parent_root}/${INPUT}"
    if [[ ! -f "$candidate" ]]; then
      die "repo-relative path '$INPUT' not found at $candidate"
    fi
  fi

  if [[ ! -f "$candidate" ]]; then
    die "agent file not readable: $candidate"
  fi

  # Derive subagent_type from filename. Tools + model live in agent.md frontmatter
  # (read by the harness at spawn time) — the resolver does not parse them here.
  subagent_type="$(basename "$candidate" .md)"
  emit_json "$subagent_type" "$candidate" "path" "$INPUT" "" '[]'
  exit 0
fi

# Name form (c/d). Plugin-prefixed names passthrough as known-good shapes.
# Bare names also passthrough as legacy back-compat (source: unknown).
case "$INPUT" in
  *:*)
    # Plugin-prefixed (e.g. kiln:debugger). The harness registered this at session start.
    emit_json "$INPUT" "" "passthrough" "$INPUT" "" '[]'
    ;;
  *)
    # Bare name — legacy back-compat. Caller may need to pass plugin-prefixed form
    # if the harness rejects the bare name.
    emit_json "$INPUT" "" "unknown" "$INPUT" "" '[]'
    ;;
esac
exit 0
