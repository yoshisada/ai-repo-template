#!/usr/bin/env bash
# preprocess.sh — workflow-JSON preprocessor for cross-plugin path resolution.
#
# Re-source guard: aligns with registry.sh / resolve.sh so engine.sh can
# unconditionally `source` this file from inside the workflow_load gate.
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

# Documentary references gotcha (FR-014, specs/merge-pr-and-sc-grep-guidance/spec.md):
#
# Authors who include documentary references to ${WHEEL_PLUGIN_<name>} or
# ${WORKFLOW_PLUGIN_DIR} inside agent `instruction:` text — even purely as prose
# describing legacy behavior — trip two failure modes:
#
#   1. The FR-F4-5 prefix-pattern tripwire fires on grammar variants that the
#      substitution regex skips (e.g., bracketed names containing characters the
#      substitution doesn't recognize), because the tripwire's prefix gate is
#      strictly `${WHEEL_PLUGIN_` or `${WORKFLOW_PLUGIN_DIR`.
#   2. `$$` escaping (`$${WHEEL_PLUGIN_<name>}`) survives the tripwire by design
#      (round-trips to a literal `${WHEEL_PLUGIN_<name>}` in the rendered output),
#      but that literal then lands in `.wheel/history/success/*.json` archives
#      where the SC-F-6 archive-grep tripwire trips it from the OTHER direction.
#
# The durable rule for documentation prose is: do NOT reproduce the token grammar
# verbatim. Substitute plain prose (e.g., "the workflow's plugin directory" or
# "the calling plugin's WHEEL_PLUGIN_<name> entry") that does not contain the
# `${...}` shape at all. This is the rule consumers see in
# plugin-wheel/README.md §Writing agent instructions.

if [[ -n "${WHEEL_PREPROCESS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
WHEEL_PREPROCESS_SH_LOADED=1

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
      printf "Wheel preprocessor failed: instruction text for step '%s' still contains '\${...}'. This is a wheel runtime bug; please file an issue.\nIf you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with \$\$ escaping.\n" "$step_id" >&2
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

# -----------------------------------------------------------------------------
# substitute_inputs_into_instruction — FR-G3-3 / FR-G3-5 / contract §4.
#
# Replaces every `{{VAR}}` placeholder in the instruction text with the
# resolved value from `resolve_inputs`. Then runs the residual-placeholder
# tripwire — if any uppercase-leading `{{NAME}}` remains, fails with the
# documented FR-G3-5 error (no agent dispatch).
#
# Pattern (narrowed per plan §3.D): `\{\{[A-Z][A-Z0-9_]*\}\}`. Mixed-case or
# lowercase `{{...}}` — e.g. mustache template literals — is invisible to
# this scan, so other templating uses don't false-positive.
#
# Args:
#   $1  instruction        — string, agent step instruction text (post-template_workflow_json)
#   $2  resolved_map_json  — single-line JSON, output of resolve_inputs
#   $3  step_id            — string, used in tripwire error
#
# Stdout (on exit 0): instruction with every `{{VAR}}` replaced.
# Stderr (on exit 1): contract §4 / FR-G3-5 hydration tripwire error.
substitute_inputs_into_instruction() {
  local instruction="$1"
  local resolved_map_json="$2"
  local step_id="$3"

  # Fast path: empty resolved map and no `{{NAME}}` placeholders → byte-identical pass-through.
  if [[ "$resolved_map_json" == "{}" || -z "$resolved_map_json" ]]; then
    if printf '%s' "$instruction" | grep -qE '\{\{[A-Z][A-Z0-9_]*\}\}'; then
      # No resolutions but still has placeholders → tripwire (FR-G3-5).
      local residuals
      residuals=$(printf '%s' "$instruction" | grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' | sort -u | tr '\n' ' ')
      printf "Hydration tripwire fired on step '%s': residual placeholder(s) %s remain after substitution. Either declare them in inputs: or remove the placeholder.\n" \
        "$step_id" "$residuals" >&2
      return 1
    fi
    printf '%s' "$instruction"
    return 0
  fi

  # Substitute via python3 (already a wheel runtime dep — same path as
  # _preprocess_substitute_string). Whole-match substitution per I-SI-1.
  local substituted
  substituted=$(INSTR="$instruction" RESOLVED="$resolved_map_json" python3 -c '
import json, os, re, sys
text = os.environ["INSTR"]
try:
    resolved = json.loads(os.environ["RESOLVED"])
except json.JSONDecodeError:
    sys.stderr.write("substitute_inputs_into_instruction: resolved map is not valid JSON\n")
    sys.exit(2)

# Substitute {{VAR}} → resolved[VAR] for every key in the map. Whole-match
# only — {{ISSUE_FILE}} matches; {{ISSUE_FILE_X}} does not collide because
# the regex includes the closing }} as a delimiter.
def _sub(m):
    name = m.group(1)
    if name in resolved:
        return str(resolved[name])
    # Leave undeclared placeholders untouched — the tripwire below catches
    # them with the offending name(s) in scope.
    return m.group(0)

text = re.sub(r"\{\{([A-Z][A-Z0-9_]*)\}\}", _sub, text)
sys.stdout.write(text)
') || {
    printf "Hydration internal error on step '%s': substitute_inputs_into_instruction failed during python3 substitution.\n" "$step_id" >&2
    return 1
  }

  # Tripwire (FR-G3-5 / I-SI-2): no `{{[A-Z]...}}` may remain post-substitution.
  if printf '%s' "$substituted" | grep -qE '\{\{[A-Z][A-Z0-9_]*\}\}'; then
    local residuals
    residuals=$(printf '%s' "$substituted" | grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' | sort -u | tr '\n' ' ')
    printf "Hydration tripwire fired on step '%s': residual placeholder(s) %s remain after substitution. Either declare them in inputs: or remove the placeholder.\n" \
      "$step_id" "${residuals% }" >&2
    return 1
  fi

  printf '%s' "$substituted"
  return 0
}
