#!/usr/bin/env bash
# resolve.sh — Agent resolution primitive (FR-A1, FR-A3)
#
# Accepts <path-or-name> and emits a single-line JSON spec on stdout:
#   { subagent_type, system_prompt_path, tools, source, canonical_path, model_default }
#
# Input forms:
#   (a) absolute path      — /abs/path/to/<name>.md
#   (b) repo-relative path — plugin-wheel/agents/<name>.md (or legacy plugin-kiln/agents/<name>.md)
#   (c) short name         — resolved via registry.json
#   (d) unknown name       — passthrough with source=unknown (back-compat for
#                            existing subagent_type: general-purpose spawns)
#
# Exit: 0 on success (including form (d)), 1 on registry/read error or empty input.
# Stderr: loud diagnostic on exit 1 — NEVER silent.
#
# Env: WORKFLOW_PLUGIN_DIR anchors forms (b) and (c) under consumer-install
# layouts where the source repo root doesn't contain plugin-wheel/.

set -euo pipefail

die() {
  echo "resolve.sh: $*" >&2
  exit 1
}

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  die "empty input — usage: resolve.sh <path-or-name>"
fi

# Locate the plugin root. Prefer $WORKFLOW_PLUGIN_DIR (consumer install layout)
# and fall back to the script's own parent (source-repo layout).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEEL_ROOT_FALLBACK="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# WORKFLOW_PLUGIN_DIR points at the plugin install dir (plugin-wheel/ equivalent).
# If set, use it; otherwise fall back to our own resolved root.
PLUGIN_ROOT="${WORKFLOW_PLUGIN_DIR:-${WHEEL_ROOT_FALLBACK}}"

REGISTRY_FILE="${PLUGIN_ROOT}/scripts/agents/registry.json"
if [[ ! -f "$REGISTRY_FILE" ]]; then
  # Last-ditch: resolve via the script's own sibling directory
  REGISTRY_FILE="${SCRIPT_DIR}/registry.json"
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    die "registry.json not found (looked in ${PLUGIN_ROOT}/scripts/agents/ and ${SCRIPT_DIR})"
  fi
fi

# Validate registry shape once.
if ! jq -e '.version == 1 and (.agents | type == "object")' "$REGISTRY_FILE" >/dev/null 2>&1; then
  die "registry.json malformed (expected .version==1 and .agents object) at $REGISTRY_FILE"
fi

emit_json() {
  # Single-line JSON on stdout.
  local subagent_type="$1" sys_path="$2" source="$3" canonical="$4" model_default="$5"
  local tools_json="$6"  # raw JSON array string
  jq -cn \
    --arg st "$subagent_type" \
    --arg sp "$sys_path" \
    --arg src "$source" \
    --arg cp "$canonical" \
    --arg md "$model_default" \
    --argjson tools "$tools_json" \
    '{subagent_type: $st, system_prompt_path: $sp, tools: $tools, source: $src, canonical_path: $cp, model_default: (if $md == "" or $md == "null" then null else $md end)}'
}

# ---- Detect form ----
# Form (a): absolute path — starts with /
# Form (b): repo-relative path — contains / (and ends with .md or is a readable file)
# Form (c): short name — no slash, no .md suffix; must be in registry
# Form (d): unknown — not in registry and not a resolvable path

is_path_form() {
  # Returns 0 if the input looks like a path (contains / or ends with .md)
  case "$1" in
    /*|*/*|*.md) return 0 ;;
    *)           return 1 ;;
  esac
}

if is_path_form "$INPUT"; then
  # Path form. Absolute or repo-relative.
  if [[ "$INPUT" = /* ]]; then
    candidate="$INPUT"
    source_form="path"
  else
    # Repo-relative. Try $PWD first (source repo), then anchor under $PLUGIN_ROOT's parent
    # (consumer install — the repo-relative form "plugin-wheel/agents/foo.md" still
    # resolves relative to the plugins cache root via $PLUGIN_ROOT).
    if [[ -f "$INPUT" ]]; then
      candidate="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
      source_form="path"
    elif [[ -z "${WORKFLOW_PLUGIN_DIR:-}" && ! -f "$INPUT" ]]; then
      # WORKFLOW_PLUGIN_DIR unset AND relative form doesn't resolve from CWD.
      die "WORKFLOW_PLUGIN_DIR unset and repo-relative path '$INPUT' not found from CWD"
    else
      # Try anchoring under PLUGIN_ROOT's parent (e.g. $WORKFLOW_PLUGIN_DIR points at
      # plugin-wheel/ install dir, so we peel back one level to resolve "plugin-wheel/agents/x.md").
      parent_root="$(cd "${PLUGIN_ROOT}/.." && pwd)"
      candidate="${parent_root}/${INPUT}"
      if [[ ! -f "$candidate" ]]; then
        die "repo-relative path '$INPUT' not found at $candidate"
      fi
      source_form="path"
    fi
  fi

  if [[ ! -f "$candidate" ]]; then
    die "agent file not readable: $candidate"
  fi

  # Look up by canonical basename in the registry to pull subagent_type/tools/model_default.
  # If the basename matches a short-name entry whose path also matches, use the registry
  # values. Otherwise fall back to deriving from filename + general-purpose defaults.
  short="$(basename "$candidate" .md)"
  entry="$(jq -c --arg k "$short" '.agents[$k] // empty' "$REGISTRY_FILE")"
  if [[ -n "$entry" ]]; then
    subagent_type="$(jq -r '.subagent_type' <<<"$entry")"
    tools="$(jq -c '.tools' <<<"$entry")"
    model_default="$(jq -r '.model_default // ""' <<<"$entry")"
    canonical="${PLUGIN_ROOT%/}/agents/${short}.md"
  else
    subagent_type="$short"
    tools='[]'
    model_default=""
    canonical="$candidate"
  fi

  emit_json "$subagent_type" "$candidate" "$source_form" "$canonical" "$model_default" "$tools"
  exit 0
fi

# Name form — consult the registry.
entry="$(jq -c --arg k "$INPUT" '.agents[$k] // empty' "$REGISTRY_FILE")"
if [[ -n "$entry" ]]; then
  # Form (c): short name resolved.
  rel_path="$(jq -r '.path' <<<"$entry")"
  subagent_type="$(jq -r '.subagent_type' <<<"$entry")"
  tools="$(jq -c '.tools' <<<"$entry")"
  model_default="$(jq -r '.model_default // ""' <<<"$entry")"

  # Resolve rel_path under $PLUGIN_ROOT's parent (so "plugin-wheel/agents/x.md" lands under
  # the repo root in source layout, or under the plugins-cache root in consumer layout).
  parent_root="$(cd "${PLUGIN_ROOT}/.." && pwd 2>/dev/null || echo "")"
  if [[ -z "$parent_root" ]]; then
    die "cannot resolve parent root for PLUGIN_ROOT=$PLUGIN_ROOT"
  fi
  sys_path="${parent_root}/${rel_path}"
  if [[ ! -f "$sys_path" ]]; then
    # Fallback: CWD-relative (some callers run from repo root).
    if [[ -f "$rel_path" ]]; then
      sys_path="$(cd "$(dirname "$rel_path")" && pwd)/$(basename "$rel_path")"
    else
      die "registry entry '$INPUT' points at '$rel_path' but file not found at $sys_path or CWD-relative"
    fi
  fi

  emit_json "$subagent_type" "$sys_path" "short-name" "$rel_path" "$model_default" "$tools"
  exit 0
fi

# Form (d): unknown name — passthrough.
# I-R1: callers relying on the pre-resolver spawn pattern MUST NOT see a behavior change.
# Emit a JSON shape that preserves the input as subagent_type so the caller can keep
# passing it to Agent() as before.
emit_json "$INPUT" "" "unknown" "$INPUT" "" '[]'
exit 0
