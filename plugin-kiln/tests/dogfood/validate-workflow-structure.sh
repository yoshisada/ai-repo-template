#!/usr/bin/env bash
# validate-workflow-structure.sh — structural gate for kiln wheel-workflow JSON.
#
# WHY: wheel's bin/validate-workflow.sh resolves workflows by NAME under a consumer
# `workflows/` dir, so it can't validate a plugin workflow file by path. This mirrors the
# checks wheel actually enforces at load/dispatch time (step types, team-reference
# integrity per lib/workflow.sh FR-024) plus the kiln reconciliation rules (no idealized
# wheel fields), so Phase 2 workflows can be gated fast without a live run. Live team
# EXECUTION is separately proven by wheel's own team fixtures.
#
# Usage: validate-workflow-structure.sh <workflow.json> [<workflow.json> ...]
# Exit: 0 all valid; 1 any failure. Prints per-file PASS/FAIL with reasons.

set -uo pipefail

# Real wheel step types (src/lib/dispatch.ts + engine.ts). Keep in sync with wheel.
KNOWN_TYPES="command agent loop branch parallel approval workflow team-create teammate team-wait team-delete"
# Fields the idealized MASTER_PLAN used that the real wheel runtime does NOT honor.
FORBIDDEN_FIELDS="model_tier on_failure"

rc=0

for wf in "$@"; do
  errs=()

  if ! jq empty "$wf" >/dev/null 2>&1; then
    echo "FAIL  $wf — not valid JSON"
    rc=1; continue
  fi

  # name + steps present
  [ "$(jq -r '.name // empty' "$wf")" = "" ] && errs+=("missing .name")
  [ "$(jq -r '(.steps | type) // "missing"' "$wf")" != "array" ] && errs+=("missing/!array .steps")

  # every step has id + a known type
  while IFS=$'\t' read -r sid stype; do
    [ -z "$sid" ] && errs+=("a step is missing .id")
    if ! printf '%s\n' $KNOWN_TYPES | grep -qx "$stype"; then
      errs+=("step '$sid': unknown type '$stype'")
    fi
  done < <(jq -r '.steps[]? | [(.id // ""), (.type // "")] | @tsv' "$wf")

  # forbidden idealized fields anywhere in a step
  for f in $FORBIDDEN_FIELDS; do
    n=$(jq --arg f "$f" '[.steps[]? | select(has($f))] | length' "$wf")
    [ "${n:-0}" -gt 0 ] && errs+=("$n step(s) use forbidden field '$f' (use concrete model / defensive exit-0)")
  done
  # on:"always" forbidden (not a real wheel field)
  na=$(jq '[.steps[]? | select(.on == "always")] | length' "$wf")
  [ "${na:-0}" -gt 0 ] && errs+=("$na step(s) use on:\"always\" (not supported)")

  # team-reference integrity (wheel lib/workflow.sh FR-024): teammate/team-wait/team-delete
  # .team must reference a team-create .id; teammate must declare a .workflow.
  team_ids=$(jq -c '[.steps[]? | select(.type=="team-create") | .id]' "$wf")
  while IFS=$'\t' read -r sid stype steam swf; do
    [ -z "$sid" ] && continue
    if [ "$steam" = "" ] || [ "$steam" = "null" ]; then
      errs+=("step '$sid' ($stype): missing .team")
    elif [ "$(jq --arg t "$steam" --argjson ids "$team_ids" -n '$ids | index($t) != null')" != "true" ]; then
      errs+=("step '$sid' ($stype): .team '$steam' does not reference a team-create step")
    fi
    if [ "$stype" = "teammate" ] && { [ "$swf" = "" ] || [ "$swf" = "null" ]; }; then
      errs+=("teammate '$sid': missing .workflow (teammates run a sub-workflow)")
    fi
  done < <(jq -r '.steps[]? | select(.type=="teammate" or .type=="team-wait" or .type=="team-delete") | [(.id // ""), .type, (.team // "null"), (.workflow // "null")] | @tsv' "$wf")

  if [ ${#errs[@]} -eq 0 ]; then
    echo "PASS  $wf"
  else
    echo "FAIL  $wf"
    for e in "${errs[@]}"; do echo "        - $e"; done
    rc=1
  fi
done

exit "$rc"
