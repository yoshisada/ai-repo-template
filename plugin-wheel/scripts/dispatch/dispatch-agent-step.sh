#!/usr/bin/env bash
# Shared dispatch helper for wheel agent steps.
#
# This file is co-owned:
# - Theme B (impl-themeB-models) owns `dispatch_agent_step_model` — resolves
#   the step's optional `model:` field to a concrete model id for spawn-time
#   injection. See contracts/interfaces.md §3 (FR-B1, FR-B2).
# - Theme A (impl-themeA-agents) owns `dispatch_agent_step_path` — resolves
#   the step's optional `agent_path:` field via the agent resolver. See
#   contracts/interfaces.md §2 (FR-A4). Added by T032.
#
# Both helpers are namespaced (`dispatch_agent_step_<field>`) so they compose:
# the dispatcher invokes each in turn and merges their output into the Agent()
# spawn instruction emitted to the orchestrator.
#
# Usage (source or exec):
#   source plugin-wheel/scripts/dispatch/dispatch-agent-step.sh
#   dispatch_agent_step_model <step-json>
#
# Portability (CC-2): all path references are anchored at the script's own
# directory so this works identically under the consumer-install layout
# (${WORKFLOW_PLUGIN_DIR}/scripts/dispatch/) and in the source repo.

set -eu

_DISPATCH_AGENT_STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# FR-B1 / FR-B2 — resolve the `model:` field on an agent step.
#
# Reads a step-JSON string from $1, extracts `.model`, and if present resolves
# it through resolve-model.sh. Emits a single-line JSON fragment to stdout:
#   { "model": "<concrete-id>" }       (resolved successfully)
#   { "model": null }                  (absent field — I-M1 backward compat)
#
# Exit codes:
#   0  — success OR absent field. Stdout carries the JSON fragment.
#   1  — `model:` was specified but resolution failed. Stderr carries the
#        identifiable error string from resolve-model.sh, PLUS a step-context
#        line:  "wheel: model resolution failed for step '<name>': <detail>"
#        Callers MUST propagate this loudly — NEVER silent fallback.
#
# Invariant (I-M1): absent `model:` → the JSON fragment has model=null and the
# dispatcher leaves the harness default alone (NFR-5 byte-identical).
# Invariant (I-M2): specified-but-unresolvable `model:` → exit 1, loud stderr.
dispatch_agent_step_model() {
  local step_json="${1:-}"
  if [[ -z "${step_json}" ]]; then
    echo "wheel: dispatch_agent_step_model: missing step JSON argument" >&2
    return 1
  fi

  local model_spec
  model_spec=$(printf '%s' "${step_json}" | jq -r '.model // empty')

  if [[ -z "${model_spec}" ]]; then
    # I-M1 — absent field is the default path. Emit explicit null so the
    # dispatcher's JSON merge has a stable shape rather than a missing key.
    jq -n '{"model": null}'
    return 0
  fi

  local step_name
  step_name=$(printf '%s' "${step_json}" | jq -r '.name // .id // "<unnamed>"')

  local resolved
  if ! resolved=$("${_DISPATCH_AGENT_STEP_DIR}/resolve-model.sh" "${model_spec}" 2>&1); then
    # resolve-model.sh already emitted its own "wheel: model resolve failed"
    # line to stderr; we propagate it via $resolved (which captured 2>&1) AND
    # add the step-context wrapper per FR-B2's required error string shape.
    echo "${resolved}" >&2
    echo "wheel: model resolution failed for step '${step_name}': ${resolved}" >&2
    return 1
  fi

  jq -n --arg m "${resolved}" '{"model": $m}'
}

# FR-A4 — resolve the `agent_path:` field on an agent step.
#
# Reads a step-JSON string from $1, extracts `.agent_path`, and if present
# resolves it through plugin-wheel/scripts/agents/resolve.sh. Emits a
# single-line JSON fragment to stdout:
#   { "agent_path": { <full resolver output> } }         (resolved from registry)
#   { "agent_path": { "source": "unknown", ... } }       (I-A3 passthrough)
#   { "agent_path": null }                               (absent field — I-A1 backward compat)
#
# Exit codes:
#   0  — success OR absent field. Stdout carries the JSON fragment.
#   1  — `agent_path:` was specified but the resolver exited 1 (file missing,
#        registry malformed, etc.). Stderr carries the resolver's diagnostic
#        PLUS a step-context line:
#        "wheel: agent_path resolution failed for step '<name>': <detail>"
#        Callers MUST propagate this loudly — NEVER silent pass (I-A4).
#
# Invariant (I-A1): absent `agent_path:` → fragment is agent_path=null; the
#   dispatcher leaves the legacy subagent_type: path alone (NFR-5).
# Invariant (I-A2): when BOTH `agent_path:` and `subagent_type:` are present,
#   the dispatcher that calls this helper MUST treat agent_path as the winner
#   and emit an INFO log line. The helper itself only resolves the field; the
#   override decision is made by the caller (keeps this helper pure).
# Invariant (I-A3): resolver emits source=unknown for unknown short names;
#   the dispatcher (not this helper) falls back to the step's subagent_type.
# Invariant (I-A4): resolver exit 1 → this helper exits 1 with a loud error.
dispatch_agent_step_path() {
  local step_json="${1:-}"
  if [[ -z "${step_json}" ]]; then
    echo "wheel: dispatch_agent_step_path: missing step JSON argument" >&2
    return 1
  fi

  local path_spec
  path_spec=$(printf '%s' "${step_json}" | jq -r '.agent_path // empty')

  if [[ -z "${path_spec}" ]]; then
    # I-A1 — absent field. Stable null so the dispatcher's merge has a known shape.
    jq -n '{"agent_path": null}'
    return 0
  fi

  local step_name
  step_name=$(printf '%s' "${step_json}" | jq -r '.name // .id // "<unnamed>"')

  # Resolver lives one directory up from dispatch/.
  local resolver="${_DISPATCH_AGENT_STEP_DIR}/../agents/resolve.sh"
  if [[ ! -x "${resolver}" ]]; then
    echo "wheel: agent_path resolver not executable at ${resolver}" >&2
    echo "wheel: agent_path resolution failed for step '${step_name}': resolver missing" >&2
    return 1
  fi

  local resolved rc
  # Run the resolver, capturing stdout separately from stderr so we can emit
  # stderr loudly while still returning stdout on the happy path. Do NOT use
  # `if !` or `||` around the command-substitution — either swallows the
  # non-zero status into a logical branch, leaving $? == 0 afterward and
  # silently shipping a "wrong exit code" regression (CC-3 forbids silent).
  local _err_tmp
  _err_tmp=$(mktemp -t wheel-dispatch-agent-path.XXXXXX)
  resolved=$("${resolver}" "${path_spec}" 2>"${_err_tmp}") || rc=$?
  : "${rc:=0}"
  if [[ "${rc}" -ne 0 ]]; then
    local diag
    diag=$(cat "${_err_tmp}" 2>/dev/null || echo "<no diagnostic>")
    rm -f "${_err_tmp}"
    echo "${diag}" >&2
    echo "wheel: agent_path resolution failed for step '${step_name}': ${diag}" >&2
    return "${rc}"
  fi
  rm -f "${_err_tmp}"

  # Validate the resolver output is a JSON object; otherwise the resolver
  # itself is buggy and we MUST fail loudly rather than ship a half-shape.
  if ! printf '%s' "${resolved}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "wheel: agent_path resolver emitted non-object JSON for step '${step_name}': ${resolved}" >&2
    return 1
  fi

  # Wrap the resolver object under an "agent_path" key so the dispatcher
  # can merge this with the model fragment emitted by dispatch_agent_step_model.
  printf '%s' "${resolved}" | jq -c '{"agent_path": .}'
}

# FR-B1 / FR-B2 — emit the teammate-spawn model clause.
#
# Usage:
#   dispatch_agent_step_model_clause <agent-name> <model-spec>
#
# Arguments:
#   <agent-name>   Display name — used in logs + the ACTIVATION ERROR string.
#   <model-spec>   The step's `model:` field value (haiku|sonnet|opus|<id>).
#                  Empty → prints nothing (NFR-5 byte-identical behavior).
#
# Stdout:
#   Empty:              absent spec (NFR-5 byte-identical path).
#   Success clause:     " Spawn this agent with model='<id>' (FR-B1 ...)."
#   Loud-fail clause:   " ACTIVATION ERROR — model resolution failed for
#                       teammate '<name>' (spec='<x>'): <detail>. Do NOT
#                       spawn this agent on default; surface the error and
#                       stop."
#
# Exit: 0 always. The loud-fail clause IS the FR-B2 invariant — the
# orchestrator reads "ACTIVATION ERROR" and stops; wheel NEVER silently
# spawns on default model (I-M2).
#
# This helper is extracted from plugin-wheel/lib/dispatch.sh's
# `_teammate_flush_from_state` so it can be unit-tested without bootstrapping
# the wheel state machine. The integration calls this; tests call it directly.
dispatch_agent_step_model_clause() {
  local agent_name="${1:-}"
  local model_spec="${2:-}"

  if [[ -z "${model_spec}" ]]; then
    return 0
  fi

  local _step_json
  _step_json=$(jq -nc --arg nm "${agent_name}" --arg m "${model_spec}" \
    '{name: $nm, model: $m}')

  local _model_frag
  if _model_frag=$(dispatch_agent_step_model "${_step_json}" 2>&1); then
    local _resolved_id
    _resolved_id=$(printf '%s' "${_model_frag}" | jq -r '.model // empty' 2>/dev/null)
    if [[ -n "${_resolved_id}" && "${_resolved_id}" != "null" ]]; then
      printf " Spawn this agent with model='%s' (FR-B1 per-step model selection)." "${_resolved_id}"
    fi
    return 0
  fi

  # FR-B2 loud-fail.
  printf " ACTIVATION ERROR — model resolution failed for teammate '%s' (spec='%s'): %s. Do NOT spawn this agent on default; surface the error and stop." \
    "${agent_name}" "${model_spec}" "${_model_frag}"
}

# If invoked as a script (not sourced), expose the helpers as a one-shot CLI
# for workflow command steps and tests. First arg is the subcommand:
#   dispatch-agent-step.sh model '<step-json>'
#   dispatch-agent-step.sh agent-path '<step-json>'
#   dispatch-agent-step.sh model-clause <agent-name> <model-spec>
#   dispatch-agent-step.sh '<step-json>'             # legacy — defaults to model
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "usage: dispatch-agent-step.sh model|agent-path|model-clause ..." >&2
    exit 2
  fi
  case "$1" in
    model)
      shift
      if [[ $# -lt 1 ]]; then
        echo "usage: dispatch-agent-step.sh model '<step-json>'" >&2
        exit 2
      fi
      dispatch_agent_step_model "$1"
      ;;
    agent-path|agent_path)
      shift
      if [[ $# -lt 1 ]]; then
        echo "usage: dispatch-agent-step.sh agent-path '<step-json>'" >&2
        exit 2
      fi
      dispatch_agent_step_path "$1"
      ;;
    model-clause)
      shift
      if [[ $# -lt 2 ]]; then
        echo "usage: dispatch-agent-step.sh model-clause <agent-name> <model-spec>" >&2
        exit 2
      fi
      dispatch_agent_step_model_clause "$1" "$2"
      ;;
    *)
      # Legacy single-arg form — preserve backward compat with Theme B's
      # initial invocation shape: one arg is a step-json and we run the model
      # helper. Kept to avoid breaking any in-flight Theme B tests.
      dispatch_agent_step_model "$1"
      ;;
  esac
fi
