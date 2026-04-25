#!/usr/bin/env bash
# preprocess.sh — workflow-JSON preprocessor for cross-plugin path resolution.
#
# Implements Theme F4 of
#   specs/cross-plugin-resolver-and-preflight-registry/spec.md
# under the contract
#   specs/cross-plugin-resolver-and-preflight-registry/contracts/interfaces.md §3.
#
# Public entrypoint:
#   template_workflow_json <workflow_json> <registry_json> <calling_plugin_dir>
#
# What it does (per FR-F4-1..F4-5):
#   1. Walks every agent step's `instruction` field.
#   2. Substitutes `${WHEEL_PLUGIN_<name>}` against `registry.plugins[<name>]`.
#   3. Substitutes `${WORKFLOW_PLUGIN_DIR}` against the calling plugin dir
#      (FR-F4-3 — subsumes the legacy Theme D Option B token).
#   4. Decodes `$${...}` to a literal `${...}` (FR-F4-4 — escape grammar).
#   5. Fires the narrowed-pattern tripwire on any residual
#      `${WHEEL_PLUGIN_*}` or `${WORKFLOW_PLUGIN_DIR*}` (FR-F4-5).
#
# Design notes:
#   - The substitution itself is delegated to a single `python3` invocation
#     per agent step. Plan §3 names `awk` for the escape pre-scan, but the
#     escape grammar requires a recorded position skip-set (research §2.B);
#     we use a sentinel-byte placeholder pattern instead, which is portable
#     and avoids gawk-vs-BSD-awk drift. `python3` is already a documented
#     wheel runtime dependency (post-tool-use.sh fallback).
#   - Generic `${VAR}` syntax (e.g. `${files[@]}`) passes through untouched
#     because the narrowed tripwire pattern only matches our two reserved
#     prefixes.
#   - The function is idempotent: a second call on already-templated output
#     finds no tokens, makes no replacements, and emits byte-identical JSON.

# Internal sentinel — stays out of user text by virtue of the SOH (\x01)
# control bytes. The bash caller decodes the sentinel back to a literal
# `${` AFTER running the tripwire scan, so escaped `$${...}` survives the
# scan without false-positiving.
_PREPROC_SENTINEL=$'\x01ESC_DOLLAR_BRACE\x01'

# Internal: substitute tokens in a single instruction string.
#
# Args:
#   $1 = instruction text
#   $2 = registry JSON (single-line, schema-stamped — the build_session_registry shape)
#   $3 = calling_plugin_dir absolute path
#
# Stdout: substituted text WITH the escape sentinel still in place at every
#         position that originally held `$${`. The caller's tripwire scan
#         operates on this intermediate form so legitimate escapes don't
#         trip the wire (research §2.B); the bash caller decodes the
#         sentinel back to `${` after the scan passes.
# Exit:   0 on completion (residuals are NOT a hard error here — that's
#         the tripwire's job, with the step id in scope).
_preprocess_substitute_string() {
  local instruction="$1"
  local registry_json="$2"
  local calling_plugin_dir="$3"

  INSTR="$instruction" REG="$registry_json" CALLER="$calling_plugin_dir" \
    SENTINEL="$_PREPROC_SENTINEL" python3 -c '
import json, os, re, sys

text = os.environ["INSTR"]
caller = os.environ["CALLER"]
SENTINEL = os.environ["SENTINEL"]

reg_raw = os.environ.get("REG", "")
try:
    reg = json.loads(reg_raw) if reg_raw else {}
except json.JSONDecodeError:
    reg = {}
plugins = reg.get("plugins", {}) if isinstance(reg, dict) else {}

# Stage 1: encode $${ to placeholder so the inner ${...} is not seen by
# the substitution regexes. Per research §2.B / I-P-3.
text = text.replace("$${", SENTINEL)

# Stage 2: substitute ${WHEEL_PLUGIN_<name>}. Optional bash-default-value
# tail (`:-/some/path`) is matched and discarded — defaults hide gaps,
# the resolver requires explicit declaration (interfaces.md §3 edge-case
# table). Names not in the registry are LEFT IN PLACE so the tripwire
# fires with the step id in scope (defense-in-depth per I-P invariants).
def _wheel_sub(m):
    name = m.group(1)
    if name in plugins:
        return plugins[name]
    return m.group(0)

text = re.sub(
    r"\$\{WHEEL_PLUGIN_([A-Za-z0-9_-]+)(?::-[^}]*)?\}",
    _wheel_sub,
    text,
)

# Stage 3: substitute ${WORKFLOW_PLUGIN_DIR} (with optional :-default
# discarded). Treated as ${WHEEL_PLUGIN_<calling-plugin>} per research §2.A.
text = re.sub(
    r"\$\{WORKFLOW_PLUGIN_DIR(?::-[^}]*)?\}",
    lambda _m: caller,
    text,
)

# NOTE: the sentinel is intentionally NOT decoded here. The bash caller
# runs the tripwire scan first, then decodes — that ordering is what
# allows a literal `$${WHEEL_PLUGIN_shelf}` in user docstrings to survive.
sys.stdout.write(text)
'
}

# Public: preprocess a workflow JSON, returning a single-line JSON with all
# agent step `instruction` fields fully templated.
#
# Args:
#   $1 = workflow_json — single-line JSON, validated by resolve_workflow_dependencies
#   $2 = registry_json — single-line JSON, output of build_session_registry
#   $3 = calling_plugin_dir — absolute path to the plugin owning this workflow file
#
# Stdout (on exit 0): single-line JSON, byte-identical to input modulo
#                     agent-step .instruction fields.
# Stderr (on exit 1): contract-mandated FR-F4-5 error string, including
#                     the offending step id.
# Exit:
#   0 — templating succeeded, tripwire passed
#   1 — tripwire fired (residual token in some agent step's instruction)
template_workflow_json() {
  local workflow_json="$1"
  local registry_json="$2"
  local calling_plugin_dir="$3"

  # Total step count drives the iteration. We rewrite agent steps in place;
  # non-agent steps pass through untouched (I-P-1 byte-identical guarantee).
  local n
  n=$(printf '%s' "$workflow_json" | jq '.steps | length')

  local result
  # Normalise to single-line input so all subsequent jq -c rewrites preserve
  # the contractually-required single-line shape (I-P-1).
  result=$(printf '%s' "$workflow_json" | jq -c '.')

  local i=0
  while ((i < n)); do
    local step_type
    step_type=$(printf '%s' "$result" | jq -r --argjson idx "$i" '.steps[$idx].type // ""')
    if [[ "$step_type" != "agent" ]]; then
      ((i++))
      continue
    fi

    local step_id
    step_id=$(printf '%s' "$result" | jq -r --argjson idx "$i" '.steps[$idx].id // ""')

    local instruction
    instruction=$(printf '%s' "$result" | jq -r --argjson idx "$i" '.steps[$idx].instruction // ""')

    if [[ -z "$instruction" ]]; then
      ((i++))
      continue
    fi

    local templated
    templated=$(_preprocess_substitute_string "$instruction" "$registry_json" "$calling_plugin_dir")

    # FR-F4-5 tripwire — narrowed pattern. Generic ${VAR} passes through
    # because the prefix gate is `WHEEL_PLUGIN_` or `WORKFLOW_PLUGIN_DIR`.
    # Run the scan BEFORE decoding the escape sentinel — that way a
    # literal `$${WHEEL_PLUGIN_shelf}` in user docstrings is invisible to
    # this grep (it shows up as the sentinel followed by the rest of the
    # token, not as a residual `${WHEEL_PLUGIN_`).
    if printf '%s' "$templated" | grep -qE '\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)'; then
      printf "Wheel preprocessor failed: instruction text for step '%s' still contains '\${...}'. This is a wheel runtime bug; please file an issue.\n" "$step_id" >&2
      return 1
    fi

    # Stage 5 (escape decode): replace the sentinel with a literal `${` so
    # `$${WHEEL_PLUGIN_shelf}` round-trips to `${WHEEL_PLUGIN_shelf}` (single
    # dollar). Bash parameter expansion handles the substitution byte-for-byte.
    templated="${templated//${_PREPROC_SENTINEL}/\$\{}"

    # Inject back into the workflow JSON. jq -c keeps the single-line shape.
    result=$(printf '%s' "$result" | jq -c --argjson idx "$i" --arg new "$templated" '.steps[$idx].instruction = $new')

    ((i++))
  done

  printf '%s' "$result"
}
