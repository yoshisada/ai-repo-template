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

# If invoked as a script (not sourced), expose dispatch_agent_step_model as a
# one-shot CLI for use inside workflow command steps and tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "usage: dispatch-agent-step.sh '<step-json>'" >&2
    exit 2
  fi
  dispatch_agent_step_model "$1"
fi
