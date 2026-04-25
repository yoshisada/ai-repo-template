#!/usr/bin/env bash
# compose-context.sh — runtime context-injection composer for agent spawns (FR-A-1..A-3).
#
# Sibling to resolve.sh per OQ-4 spec-phase decision. Emits a single-line JSON object:
#   { subagent_type, prompt_prefix, model_default }
#
# The calling skill is responsible for prepending `prompt_prefix` to its task prompt
# before calling Agent. The composer NEVER calls Agent itself (I-A2).
#
# Usage:
#   compose-context.sh \
#     --agent-name <name> \
#     --plugin-id <id> \
#     --task-spec <path-to-json> \
#     [--prd-path <path>]
#
# Required env:
#   WORKFLOW_PLUGIN_DIR   Absolute path to orchestrating plugin. Anchors the
#                         "WORKFLOW_PLUGIN_DIR=..." line in the prompt prefix.
#
# Exit codes (per contracts/interfaces.md §2):
#   0 success
#   1 task_spec invalid (missing required field, malformed JSON)
#   2 task_shape not in closed vocabulary (FR-A-6)
#   3 agent_name not declared in plugin manifest's agent_bindings
#   4 verb in agent_bindings or agent_binding_overrides not in closed namespace
#   5 agent_binding_overrides references an agent not in agent_bindings (SC-5)
#   6 WORKFLOW_PLUGIN_DIR unset or path does not exist
#   7 required input file (manifest, stanza, coordination protocol) missing
#
# Stderr carries a human-readable diagnostic on every non-zero exit (I-A4).

set -euo pipefail
export LC_ALL=C   # NFR-6 determinism — sort uses byte order, not locale.

die() {
  local code="$1"; shift
  echo "compose-context.sh: $*" >&2
  exit "$code"
}

# --- Argument parsing ---
AGENT_NAME=""
PLUGIN_ID=""
TASK_SPEC=""
PRD_PATH=""

while (( $# > 0 )); do
  case "$1" in
    --agent-name) AGENT_NAME="${2:-}"; shift 2 ;;
    --plugin-id)  PLUGIN_ID="${2:-}";  shift 2 ;;
    --task-spec)  TASK_SPEC="${2:-}";  shift 2 ;;
    --prd-path)   PRD_PATH="${2:-}";   shift 2 ;;
    *) die 1 "unknown argument: $1" ;;
  esac
done

[[ -z "$AGENT_NAME" ]] && die 1 "missing --agent-name"
[[ -z "$PLUGIN_ID"  ]] && die 1 "missing --plugin-id"
[[ -z "$TASK_SPEC"  ]] && die 1 "missing --task-spec"

# --- Path anchoring ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEEL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PLUGINS_PARENT="$(cd "${WHEEL_ROOT}/.." && pwd)"

VERBS_INDEX="${SCRIPT_DIR}/verbs/_index.json"
SHAPES_INDEX="${PLUGINS_PARENT}/plugin-kiln/lib/task-shapes/_index.json"
SHAPES_DIR="${PLUGINS_PARENT}/plugin-kiln/lib/task-shapes"
COORD_PROTO="${PLUGINS_PARENT}/plugin-kiln/agents/_shared/coordination-protocol.md"
MANIFEST="${PLUGINS_PARENT}/plugin-${PLUGIN_ID}/.claude-plugin/plugin.json"

# --- Env validation (exit 6) ---
if [[ -z "${WORKFLOW_PLUGIN_DIR:-}" ]]; then
  die 6 "WORKFLOW_PLUGIN_DIR unset"
fi
if [[ ! -d "$WORKFLOW_PLUGIN_DIR" ]]; then
  die 6 "WORKFLOW_PLUGIN_DIR path does not exist: $WORKFLOW_PLUGIN_DIR"
fi

# --- Required input file existence (exit 7) ---
[[ ! -f "$VERBS_INDEX"  ]] && die 7 "verb index missing: $VERBS_INDEX"
[[ ! -f "$SHAPES_INDEX" ]] && die 7 "task-shape index missing: $SHAPES_INDEX"
[[ ! -f "$MANIFEST"     ]] && die 7 "plugin manifest missing: $MANIFEST"

# --- Task spec parse + validate (exits 1, 2) ---
[[ ! -f "$TASK_SPEC" ]] && die 1 "task-spec file not found: $TASK_SPEC"
if ! jq -e . "$TASK_SPEC" >/dev/null 2>&1; then
  die 1 "task-spec is not valid JSON: $TASK_SPEC"
fi

TASK_SHAPE="$(jq -r '.task_shape // ""' "$TASK_SPEC")"
TASK_SUMMARY="$(jq -r '.task_summary // ""' "$TASK_SPEC")"
[[ -z "$TASK_SHAPE"   ]] && die 1 "task_spec missing required field: task_shape"
[[ -z "$TASK_SUMMARY" ]] && die 1 "task_spec missing required field: task_summary"

# Variables and axes are optional (default {} and []).
VARIABLES_JSON="$(jq -c '.variables // {}' "$TASK_SPEC")"
AXES_JSON="$(jq -c '.axes // []' "$TASK_SPEC")"

# Validate task_shape against closed vocabulary.
SHAPE_OK="$(jq -r --arg s "$TASK_SHAPE" '
  .shapes // [] | index($s) | if . == null then "no" else "yes" end
' "$SHAPES_INDEX")"
if [[ "$SHAPE_OK" != "yes" ]]; then
  closed_list="$(jq -r '.shapes | join(", ")' "$SHAPES_INDEX")"
  die 2 "unknown task_shape '$TASK_SHAPE' — closed vocabulary: $closed_list"
fi

SHAPE_STANZA="${SHAPES_DIR}/${TASK_SHAPE}.md"
[[ ! -f "$SHAPE_STANZA" ]] && die 7 "task-shape stanza missing: $SHAPE_STANZA"
[[ ! -f "$COORD_PROTO"  ]] && die 7 "coordination-protocol stanza missing: $COORD_PROTO"

# --- Manifest agent lookup (exit 3) ---
if ! jq -e --arg a "$AGENT_NAME" '.agent_bindings[$a]' "$MANIFEST" >/dev/null 2>&1; then
  die 3 "agent '$AGENT_NAME' not declared in plugin-${PLUGIN_ID} agent_bindings"
fi

# Manifest verb table for this agent (object: verb -> command).
MANIFEST_VERBS="$(jq -c --arg a "$AGENT_NAME" '
  .agent_bindings[$a].verbs // {}
' "$MANIFEST")"

# --- Verb namespace validation against manifest (exit 4) ---
ALLOWED_VERBS="$(jq -c '.verbs' "$VERBS_INDEX")"
BAD_MANIFEST_VERB="$(jq -nr --argjson allowed "$ALLOWED_VERBS" --argjson m "$MANIFEST_VERBS" '
  $m | keys[] as $v | select(($allowed | index($v)) | not) | $v
' | head -1)"
if [[ -n "$BAD_MANIFEST_VERB" ]]; then
  closed_list="$(jq -r '.verbs | join(", ")' "$VERBS_INDEX")"
  die 4 "unknown verb '$BAD_MANIFEST_VERB' for agent '$AGENT_NAME' in manifest — closed namespace: $closed_list"
fi

# --- PRD overrides (optional; exits 4, 5) ---
OVERRIDES_JSON="{}"
if [[ -n "$PRD_PATH" ]]; then
  [[ ! -f "$PRD_PATH" ]] && die 1 "prd-path file not found: $PRD_PATH"
  # Convert YAML frontmatter agent_binding_overrides block to JSON via python3.
  OVERRIDES_JSON="$(python3 - "$PRD_PATH" <<'PYEOF'
import re, sys, json
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()
m = re.match(r'^---\s*\n(.*?)\n---\s*(?:\n|$)', text, re.DOTALL)
if not m:
    print('{}'); sys.exit(0)
fm = m.group(1)
overrides = {}
in_overrides = False
current_agent = None
in_verbs = False
for raw in fm.splitlines():
    line = raw.rstrip()
    if not line.strip():
        continue
    # Top-level key (no indent) — toggles in/out of overrides block.
    if re.match(r'^[A-Za-z]', line):
        in_overrides = (re.match(r'^agent_binding_overrides\s*:\s*$', line) is not None)
        current_agent = None
        in_verbs = False
        continue
    if not in_overrides:
        continue
    # 2-space indent — agent name.
    m2 = re.match(r'^  ([A-Za-z0-9_-]+)\s*:\s*$', line)
    if m2:
        current_agent = m2.group(1)
        overrides[current_agent] = {'verbs': {}}
        in_verbs = False
        continue
    # 4-space indent — `verbs:` key.
    if re.match(r'^    verbs\s*:\s*$', line):
        in_verbs = True
        continue
    # 6-space indent — verb: command.
    if in_verbs and current_agent is not None:
        m3 = re.match(r'^      ([A-Za-z0-9_-]+)\s*:\s*(.*)$', line)
        if m3:
            cmd = m3.group(2).strip()
            # Strip surrounding quotes (single or double) if present.
            if (cmd.startswith('"') and cmd.endswith('"')) or (cmd.startswith("'") and cmd.endswith("'")):
                cmd = cmd[1:-1]
            overrides[current_agent]['verbs'][m3.group(1)] = cmd
print(json.dumps(overrides))
PYEOF
)"
  if [[ -z "$OVERRIDES_JSON" ]]; then
    OVERRIDES_JSON="{}"
  fi
fi

# --- Override validation: agent must exist in manifest (exit 5), verbs must be in namespace (exit 4) ---
if [[ "$OVERRIDES_JSON" != "{}" ]]; then
  # Unknown agent in overrides.
  BAD_AGENT="$(jq -r --slurpfile m <(jq '.agent_bindings // {}' "$MANIFEST") '
    keys[] as $a | select(($m[0] | has($a)) | not) | $a
  ' <<<"$OVERRIDES_JSON" | head -1)"
  if [[ -n "$BAD_AGENT" ]]; then
    die 5 "agent_binding_overrides references unknown agent '$BAD_AGENT' (not in plugin-${PLUGIN_ID} agent_bindings)"
  fi
  # Unknown verb in overrides (any agent).
  BAD_VERB="$(jq -r --argjson allowed "$ALLOWED_VERBS" '
    to_entries[]
    | .key as $a
    | (.value.verbs // {}) | keys[] as $v
    | select(($allowed | index($v)) | not)
    | $v
  ' <<<"$OVERRIDES_JSON" | head -1)"
  if [[ -n "$BAD_VERB" ]]; then
    closed_list="$(jq -r '.verbs | join(", ")' "$VERBS_INDEX")"
    die 4 "unknown verb '$BAD_VERB' in agent_binding_overrides — closed namespace: $closed_list"
  fi
fi

# --- Compute effective verb table (manifest defaults + per-verb overrides for this agent) ---
EFFECTIVE_VERBS="$(jq -c --argjson o "$OVERRIDES_JSON" --arg a "$AGENT_NAME" '
  . as $base
  | (($o[$a].verbs // {})) as $ov
  | $base + $ov
' <<<"$MANIFEST_VERBS")"

# --- Read agent model_default from agent.md frontmatter (null if absent) ---
AGENT_MD="${PLUGINS_PARENT}/plugin-${PLUGIN_ID}/agents/${AGENT_NAME}.md"
MODEL_DEFAULT_RAW=""
if [[ -f "$AGENT_MD" ]]; then
  # Read first frontmatter block, look for `model:` line. Allowed values: haiku|sonnet|opus|<id>|null.
  MODEL_DEFAULT_RAW="$(awk '
    BEGIN { fm_seen=0; in_fm=0 }
    /^---[[:space:]]*$/ {
      if (!fm_seen) { fm_seen=1; in_fm=1; next }
      else if (in_fm) { exit }
    }
    in_fm && /^model:[[:space:]]/ {
      sub(/^model:[[:space:]]*/, "")
      gsub(/^["\x27]|["\x27][[:space:]]*$/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$AGENT_MD")"
fi

# --- Assemble prompt_prefix ---
{
  printf '## Runtime Environment\n\n'
  printf 'WORKFLOW_PLUGIN_DIR=%s\n\n' "$WORKFLOW_PLUGIN_DIR"
  printf '### Task\n\n'
  printf -- '- task_shape: %s\n' "$TASK_SHAPE"
  printf -- '- task_summary: %s\n\n' "$TASK_SUMMARY"

  # Variables section — omit entirely if empty (per contract §2).
  VAR_COUNT="$(jq 'length' <<<"$VARIABLES_JSON")"
  if [[ "$VAR_COUNT" -gt 0 ]]; then
    printf '### Variables\n\n'
    printf '| Key | Value |\n'
    printf '|---|---|\n'
    jq -r 'to_entries | sort_by(.key)[] | "| \(.key) | \(.value) |"' <<<"$VARIABLES_JSON"
    printf '\n'
  fi

  # Verbs section — always present (even if empty agent_bindings, the table renders empty rows).
  printf '### Verbs\n\n'
  printf '| Verb | Command |\n'
  printf '|---|---|\n'
  jq -r 'to_entries | sort_by(.key)[] | "| \(.key) | \(.value) |"' <<<"$EFFECTIVE_VERBS"
  printf '\n'

  # Axes section — omit if empty.
  AX_COUNT="$(jq 'length' <<<"$AXES_JSON")"
  if [[ "$AX_COUNT" -gt 0 ]]; then
    printf '### Axes\n\n'
    jq -r '.[] | "- \(.)"' <<<"$AXES_JSON"
    printf '\n'
  fi

  # Per-shape stanza — verbatim body of plugin-kiln/lib/task-shapes/<shape>.md.
  printf '### Task Shape: %s\n\n' "$TASK_SHAPE"
  cat "$SHAPE_STANZA"
  # Ensure stanza ends with single newline before next section.
  printf '\n'

  # Coordination protocol — verbatim body.
  printf '### Coordination Protocol\n\n'
  cat "$COORD_PROTO"
} > /tmp/compose-context-prefix.$$.md

PREFIX_FILE="/tmp/compose-context-prefix.$$.md"
trap 'rm -f "$PREFIX_FILE"' EXIT

# --- Emit final JSON ---
SUBAGENT_TYPE="${PLUGIN_ID}:${AGENT_NAME}"

jq -cn \
  --arg st "$SUBAGENT_TYPE" \
  --rawfile pp "$PREFIX_FILE" \
  --arg md "$MODEL_DEFAULT_RAW" \
  '{
     subagent_type: $st,
     prompt_prefix: $pp,
     model_default: (if $md == "" or $md == "null" then null else $md end)
   }'
