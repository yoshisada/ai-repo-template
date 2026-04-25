#!/usr/bin/env bash
# FR-B1 / FR-B2 — Per-step model resolver.
#
# Usage:
#   resolve-model.sh <model-spec>
#
# Arguments:
#   <model-spec>  One of:
#                   "haiku"    → project-default haiku id (from model-defaults.json)
#                   "sonnet"   → project-default sonnet id
#                   "opus"     → project-default opus id
#                   "<id>"     → passed through if it matches ^claude-[a-z0-9-]+$
#
# Exit codes:
#   0  — resolved successfully, concrete model id on stdout
#   1  — unrecognized tier, malformed id, or missing model-defaults.json
#
# Invariant (I-M2, FR-B2): NEVER silent fallback. Unrecognized input exits 1
# with an identifiable error string on stderr — callers propagate this loudly
# so dispatch surfaces the failure rather than silently running on a default
# model (which is the original bug shape this PRD closes).
#
# Invariant (I-M3): explicit-id validation is regex-only. The resolver does
# not round-trip the id to the harness; a harness rejection surfaces at
# dispatch time, also loudly.
#
# Portability (CC-2): this script resolves model-defaults.json via its own
# directory (script-adjacent), so it works identically in the source repo and
# under the consumer-install layout (WORKFLOW_PLUGIN_DIR/scripts/dispatch/).

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/model-defaults.json"

# Identifiable error prefix — the FR-B2 loud-failure fingerprint. Tests grep
# for this string; do NOT change it without also updating the tripwire tests.
ERR_PREFIX="wheel: model resolve failed"

die() {
  echo "${ERR_PREFIX}: $*" >&2
  exit 1
}

if [[ $# -lt 1 ]]; then
  die "missing argument: expected <model-spec> (haiku|sonnet|opus|<explicit-id>)"
fi

MODEL_SPEC="$1"

if [[ -z "${MODEL_SPEC}" ]]; then
  die "empty model spec"
fi

if [[ ! -f "${DEFAULTS_FILE}" ]]; then
  die "model-defaults.json not found at ${DEFAULTS_FILE}"
fi

case "${MODEL_SPEC}" in
  haiku|sonnet|opus)
    # Tier form: look up in model-defaults.json.
    resolved=$(jq -r --arg tier "${MODEL_SPEC}" '.tiers[$tier] // empty' "${DEFAULTS_FILE}") \
      || die "jq failed reading ${DEFAULTS_FILE}"
    if [[ -z "${resolved}" || "${resolved}" == "null" ]]; then
      die "tier '${MODEL_SPEC}' not present in ${DEFAULTS_FILE}"
    fi
    # Defensive: even the looked-up value must be a well-shaped id.
    if ! [[ "${resolved}" =~ ^claude-[a-z0-9-]+$ ]]; then
      die "tier '${MODEL_SPEC}' resolved to malformed id '${resolved}' (expected ^claude-[a-z0-9-]+$)"
    fi
    printf '%s\n' "${resolved}"
    ;;
  *)
    # Explicit-id form: regex-validate. No round-trip to the harness (I-M3).
    if [[ "${MODEL_SPEC}" =~ ^claude-[a-z0-9-]+$ ]]; then
      printf '%s\n' "${MODEL_SPEC}"
    else
      die "unrecognized model spec '${MODEL_SPEC}' — expected 'haiku|sonnet|opus' or an explicit id matching ^claude-[a-z0-9-]+$"
    fi
    ;;
esac
