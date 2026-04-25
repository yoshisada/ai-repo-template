#!/usr/bin/env bash
# step-dispatch-background-sync.sh — batched wrapper for the deterministic bash
# chain the background sub-agent runs inside the `dispatch-background-sync` step
# of `kiln:kiln-report-issue`.
#
# Pre-consolidation, this chain was 3 separate Bash tool invocations inside the
# background sub-agent's prompt:
#   1. shelf-counter.sh increment-and-decide   → stdout: {"before":N,"after":N,"threshold":N,"action":"..."}
#   2. append-bg-log.sh <b> <a> <t> <action>    → appends one log line
#   3. (conditional on action=full-sync) invoke /shelf:shelf-sync + /shelf:shelf-propose-manifest-improvement
#
# This wrapper consolidates steps 1+2 into a single script so the background
# sub-agent can execute them with one Bash tool call instead of two. Step 3
# remains agent-side because it invokes Skills, not bash — see the audit doc
# at .kiln/research/wheel-step-batching-audit-2026-04-24.md.
#
# Contract: specs/wheel-as-runtime/contracts/interfaces.md §6 (I-B1..I-B5).
# Owner: impl-themeE-batching (FR-E2).

set -e
set -u
set -o pipefail

STEP_NAME="dispatch-background-sync"
LOG_PREFIX="wheel:${STEP_NAME}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "${LOG_PREFIX}: start | $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- Action 1: increment counter and decide action ----
echo "${LOG_PREFIX}: action=counter-increment-and-decide | start"
COUNTER_JSON="$(bash "${SELF_DIR}/shelf-counter.sh" increment-and-decide)"
# Validate JSON shape. If malformed, set -e won't fire (jq -e is explicit).
BEFORE="$(printf '%s' "${COUNTER_JSON}" | jq -e -r '.before')"
AFTER="$(printf '%s' "${COUNTER_JSON}" | jq -e -r '.after')"
THRESHOLD="$(printf '%s' "${COUNTER_JSON}" | jq -e -r '.threshold')"
ACTION="$(printf '%s' "${COUNTER_JSON}" | jq -e -r '.action')"
echo "${LOG_PREFIX}: action=counter-increment-and-decide | ok | before=${BEFORE} after=${AFTER} threshold=${THRESHOLD} next=${ACTION}"

# ---- Action 2: append background-log line ----
echo "${LOG_PREFIX}: action=append-bg-log | start"
bash "${SELF_DIR}/append-bg-log.sh" "${BEFORE}" "${AFTER}" "${THRESHOLD}" "${ACTION}" "" >/dev/null
echo "${LOG_PREFIX}: action=append-bg-log | ok"

# ---- Final structured stdout signal ----
# Contract I-B3: single-line JSON on stdout as the LAST stdout line before
# the "done" echo. The calling step parses this for success/failure.
jq -c -n \
  --arg step "${STEP_NAME}" \
  --arg status "ok" \
  --argjson before "${BEFORE}" \
  --argjson after "${AFTER}" \
  --argjson threshold "${THRESHOLD}" \
  --arg next_action "${ACTION}" \
  '{step: $step, status: $status, actions: ["counter-increment-and-decide","append-bg-log"], counter: {before: $before, after: $after, threshold: $threshold}, next_action: $next_action}'

echo "${LOG_PREFIX}: done | $(date -u +%Y-%m-%dT%H:%M:%SZ)"
