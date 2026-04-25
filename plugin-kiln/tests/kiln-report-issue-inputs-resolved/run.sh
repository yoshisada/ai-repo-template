#!/usr/bin/env bash
# T066 — kiln-report-issue-inputs-resolved fixture.
#
# FR-G4 / User Story 1 (US1-1, US1-2, US1-3) + User Story 5 structural anchor.
#
# Exercises the hook-time hydration pipeline against the MIGRATED
# `plugin-kiln/workflows/kiln-report-issue.json` with a synthetic state
# where the `write-issue-note` upstream step has produced its result file
# and `.shelf-config` is seeded. Asserts the structural migration outcome:
#
#   (a) workflow_load + workflow_validate_inputs_outputs accept the migrated JSON.
#   (b) `_parse_jsonpath_expr` accepts every input expression in the migrated
#       step (5 entries — ISSUE_FILE, OBSIDIAN_PATH, CURRENT_COUNTER, THRESHOLD,
#       SHELF_DIR).
#   (c) `resolve_inputs` resolves all 5 values against the synthetic state +
#       config + registry.
#   (d) `context_build` emits the "## Resolved Inputs" block listing all 5
#       values when called with the resolved map (FR-G3-2).
#   (e) `context_build` SUPPRESSES the legacy "## Context from Previous Steps"
#       footer (FR-G1-3) for the migrated step.
#   (f) `substitute_inputs_into_instruction` substitutes every `{{VAR}}`
#       placeholder in the dispatched instruction (FR-G3-3).
#   (g) Tripwire (FR-G3-5): zero residual `{{[A-Z][A-Z0-9_]*}}` patterns
#       remain in the substituted instruction.
#   (h) SC-G-1 recalibrated: dispatched instruction contains zero of the
#       removed disk-fetch sub-commands —
#         - `bash "${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh" read`
#         - `jq -r '.issue_file, .obsidian_path' .wheel/outputs/shelf-write-issue-note-result.json`
#       (the migrated workflow uses `{{SHELF_DIR}}` for cross-plugin paths;
#       the post-substitution form is the absolute install path, not the
#       legacy `${WHEEL_PLUGIN_shelf}` token.)
#
# Live-smoke (NFR-G-4) is the AUDITOR's job (T081-T082) — this fixture
# locks the structural migration outcome without putting an LLM in the loop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export WHEEL_LIB_DIR="${REPO_ROOT}/plugin-wheel/lib"

# shellcheck source=../../../plugin-wheel/lib/workflow.sh
source "${WHEEL_LIB_DIR}/workflow.sh"
# shellcheck source=../../../plugin-wheel/lib/resolve_inputs.sh
source "${WHEEL_LIB_DIR}/resolve_inputs.sh"
# shellcheck source=../../../plugin-wheel/lib/context.sh
source "${WHEEL_LIB_DIR}/context.sh"
# shellcheck source=../../../plugin-wheel/lib/preprocess.sh
source "${WHEEL_LIB_DIR}/preprocess.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
nok() { fail=$((fail+1)); echo "FAIL: $1" >&2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kiln-report-issue-inputs-resolved-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

WF_PATH="${REPO_ROOT}/plugin-kiln/workflows/kiln-report-issue.json"

# -----------------------------------------------------------------------------
# (a) workflow_load + workflow_validate_inputs_outputs accept the migrated JSON.
# -----------------------------------------------------------------------------
load_stderr="${TMP}/load-stderr"
if WORKFLOW_JSON=$(workflow_load "$WF_PATH" 2>"$load_stderr"); then
  ok "(a) workflow_load accepts migrated kiln-report-issue.json"
else
  nok "(a) workflow_load REJECTED migrated JSON — stderr: $(cat "$load_stderr")"
  exit 1
fi

# Sanity: confirm the migration shape.
version=$(printf '%s' "$WORKFLOW_JSON" | jq -r '.version')
inputs_count=$(printf '%s' "$WORKFLOW_JSON" | jq '[.steps[] | select(.id=="dispatch-background-sync") | .inputs | keys] | flatten | length')
schema_step_count=$(printf '%s' "$WORKFLOW_JSON" | jq '[.steps[] | select(.output_schema != null)] | length')
if [[ "$version" == "3.2.0" ]]; then
  ok "(a) workflow version bumped to 3.2.0"
else
  nok "(a) workflow version is '$version', expected '3.2.0'"
fi
if [[ "$inputs_count" == "5" ]]; then
  ok "(a) dispatch-background-sync declares 5 inputs"
else
  nok "(a) dispatch-background-sync has $inputs_count inputs, expected 5"
fi
if [[ "$schema_step_count" == "2" ]]; then
  ok "(a) 2 steps declare output_schema (create-issue + write-issue-note)"
else
  nok "(a) $schema_step_count steps declare output_schema, expected 2"
fi

# -----------------------------------------------------------------------------
# (b) _parse_jsonpath_expr accepts every input expression.
# -----------------------------------------------------------------------------
inputs_json=$(printf '%s' "$WORKFLOW_JSON" | jq -c '.steps[] | select(.id=="dispatch-background-sync") | .inputs')
parse_failures=0
for var in ISSUE_FILE OBSIDIAN_PATH CURRENT_COUNTER THRESHOLD SHELF_DIR; do
  expr=$(printf '%s' "$inputs_json" | jq -r --arg k "$var" '.[$k]')
  if ! _parse_jsonpath_expr "$expr"; then
    parse_failures=$((parse_failures + 1))
    echo "  parse failed for $var=$expr" >&2
  fi
done
if [[ "$parse_failures" -eq 0 ]]; then
  ok "(b) all 5 input expressions parse via _parse_jsonpath_expr"
else
  nok "(b) $parse_failures input expressions failed to parse"
fi

# -----------------------------------------------------------------------------
# Set up synthetic state for resolve_inputs.
# - write-issue-note step has produced .wheel/outputs/shelf-write-issue-note-result.json
# - .shelf-config has shelf_full_sync_counter + shelf_full_sync_threshold
# - session registry has shelf plugin
# -----------------------------------------------------------------------------
mkdir -p "${TMP}/.wheel/outputs" "${TMP}/.shelf-fake"

# Sub-workflow alias output file (per researcher-baseline §Job 2 quirk).
cat > "${TMP}/.wheel/outputs/shelf-write-issue-note-result.json" <<'EOF'
{
  "issue_file": ".kiln/issues/2026-04-25-fixture-test.md",
  "obsidian_path": "@second-brain/projects/ai-repo-template/issues/2026-04-25-fixture-test.md"
}
EOF

# Synthetic .shelf-config in TMP.
cat > "${TMP}/.shelf-config" <<'EOF'
shelf_full_sync_counter = 3
shelf_full_sync_threshold = 10
slug = ai-repo-template
EOF

# Synthetic state file: 4 steps, write-issue-note (idx=2) is "done".
STATE_JSON=$(jq -nc \
  --arg out_dir "${TMP}/.wheel/outputs" \
  '{
    name: "kiln-report-issue",
    session_id: "fixture-session",
    current_step: 3,
    steps: [
      {id: "check-existing-issues", status: "done", output: ".wheel/outputs/check-existing-issues.txt"},
      {id: "create-issue", status: "done", output: ".wheel/outputs/create-issue-result.md"},
      {id: "write-issue-note", status: "done", output: ""},
      {id: "dispatch-background-sync", status: "pending"}
    ]
  }')

# Synthetic registry — shelf plugin pointing at a fake install dir.
REGISTRY_JSON=$(jq -nc --arg shelfp "${TMP}/.shelf-fake" \
  '{schema_version: 1, plugins: {shelf: $shelfp, kiln: "/dev/null", wheel: "/dev/null"}}')

DISPATCH_STEP=$(printf '%s' "$WORKFLOW_JSON" | jq -c '.steps[] | select(.id=="dispatch-background-sync")')

# -----------------------------------------------------------------------------
# (c) resolve_inputs resolves all 5 values.
# Need to run from TMP cwd so the relative .shelf-config and
# .wheel/outputs/shelf-write-issue-note-result.json paths resolve.
# -----------------------------------------------------------------------------
resolve_stderr="${TMP}/resolve-stderr"
RESOLVED_MAP=$(cd "$TMP" && resolve_inputs "$DISPATCH_STEP" "$STATE_JSON" "$WORKFLOW_JSON" "$REGISTRY_JSON" 2>"$resolve_stderr")
resolve_rc=$?

if [[ "$resolve_rc" -eq 0 && -n "$RESOLVED_MAP" && "$RESOLVED_MAP" != "{}" ]]; then
  ok "(c) resolve_inputs returned non-empty resolved map (rc=0)"
else
  nok "(c) resolve_inputs failed — rc=$resolve_rc, stderr: $(cat "$resolve_stderr"), map: $RESOLVED_MAP"
  exit 1
fi

# Spot-check each of the 5 resolved values.
expect_value() {
  local key="$1" want="$2"
  local got
  got=$(printf '%s' "$RESOLVED_MAP" | jq -r --arg k "$key" '.[$k] // ""')
  if [[ "$got" == "$want" ]]; then
    ok "(c) resolved $key = '$got'"
  else
    nok "(c) resolved $key = '$got', expected '$want'"
  fi
}
expect_value "ISSUE_FILE" ".kiln/issues/2026-04-25-fixture-test.md"
expect_value "OBSIDIAN_PATH" "@second-brain/projects/ai-repo-template/issues/2026-04-25-fixture-test.md"
expect_value "CURRENT_COUNTER" "3"
expect_value "THRESHOLD" "10"
expect_value "SHELF_DIR" "${TMP}/.shelf-fake"

# -----------------------------------------------------------------------------
# (d) + (e) context_build emits "## Resolved Inputs" + suppresses footer.
# -----------------------------------------------------------------------------
ctx_out=$(context_build "$DISPATCH_STEP" "$STATE_JSON" "$WORKFLOW_JSON" "$RESOLVED_MAP" 2>/dev/null)

if [[ "$ctx_out" == *"## Resolved Inputs"* ]]; then
  ok "(d) '## Resolved Inputs' block present in context_build output"
else
  nok "(d) '## Resolved Inputs' block absent — output head: $(printf '%s' "$ctx_out" | head -20)"
fi

# All 5 var names must appear in the resolved-inputs block.
missing_vars=0
for var in ISSUE_FILE OBSIDIAN_PATH CURRENT_COUNTER THRESHOLD SHELF_DIR; do
  if [[ "$ctx_out" != *"$var"* ]]; then
    missing_vars=$((missing_vars + 1))
    echo "  resolved-inputs block missing var: $var" >&2
  fi
done
if [[ "$missing_vars" -eq 0 ]]; then
  ok "(d) all 5 var names present in resolved-inputs block"
else
  nok "(d) $missing_vars var names missing from resolved-inputs block"
fi

if [[ "$ctx_out" != *"## Context from Previous Steps"* ]]; then
  ok "(e) FR-G1-3: legacy '## Context from Previous Steps' footer SUPPRESSED when inputs: declared"
else
  nok "(e) legacy footer leaked through despite inputs: declaration"
fi

# -----------------------------------------------------------------------------
# (f) + (g) substitute_inputs_into_instruction + tripwire.
# Pull the dispatch step's instruction body and run substitution. Verify all
# {{VAR}} placeholders are replaced AND no residual placeholder remains.
# -----------------------------------------------------------------------------
INSTRUCTION=$(printf '%s' "$DISPATCH_STEP" | jq -r '.instruction')

# Count {{VAR}} placeholders BEFORE substitution.
pre_count=$(printf '%s' "$INSTRUCTION" | grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' | wc -l | tr -d ' ')
if [[ "$pre_count" -gt 0 ]]; then
  ok "(f) instruction has $pre_count {{VAR}} placeholders pre-substitution"
else
  nok "(f) instruction has zero {{VAR}} placeholders pre-substitution — migration didn't add them"
fi

sub_stderr="${TMP}/sub-stderr"
SUBSTITUTED=$(substitute_inputs_into_instruction "$INSTRUCTION" "$RESOLVED_MAP" "dispatch-background-sync" 2>"$sub_stderr")
sub_rc=$?

if [[ "$sub_rc" -eq 0 ]]; then
  ok "(f) substitute_inputs_into_instruction succeeded (rc=0)"
else
  nok "(f) substitution failed — rc=$sub_rc, stderr: $(cat "$sub_stderr")"
fi

# (g) Tripwire post-substitution count.
post_count=$(printf '%s' "$SUBSTITUTED" | grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' | wc -l | tr -d ' ')
if [[ "$post_count" -eq 0 ]]; then
  ok "(g) zero {{VAR}} residuals post-substitution (FR-G3-5 tripwire would not fire)"
else
  nok "(g) $post_count {{VAR}} residuals leaked through substitution"
  printf '%s' "$SUBSTITUTED" | grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' | sort -u >&2
fi

# Expected resolved values must appear in substituted instruction.
expect_substituted() {
  local needle="$1"
  if [[ "$SUBSTITUTED" == *"$needle"* ]]; then
    ok "(f) substituted instruction contains '$needle'"
  else
    nok "(f) substituted instruction does NOT contain '$needle'"
  fi
}
expect_substituted ".kiln/issues/2026-04-25-fixture-test.md"
expect_substituted "@second-brain/projects/ai-repo-template/issues/2026-04-25-fixture-test.md"

# -----------------------------------------------------------------------------
# (h) SC-G-1 recalibrated: zero in-step disk-fetch sub-commands.
# -----------------------------------------------------------------------------
# The migration must DELETE these from the instruction body:
#   1. `bash "${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh" read`
#      (CURRENT_COUNTER + THRESHOLD now from $config inputs)
#   2. `jq -r '.issue_file, .obsidian_path' .wheel/outputs/shelf-write-issue-note-result.json`
#      (ISSUE_FILE + OBSIDIAN_PATH now from $.steps inputs)
#
# We grep against BOTH the raw instruction (pre-substitution) and the post-
# substitution form (the dispatched prompt). Both must be free of these
# specific disk fetches.

forbidden=(
  "shelf-counter.sh\" read"
  "shelf-counter.sh' read"
  "jq -r '.issue_file, .obsidian_path'"
  ".wheel/outputs/shelf-write-issue-note-result.json"
)

found_disk_fetches=0
for needle in "${forbidden[@]}"; do
  if printf '%s' "$INSTRUCTION" | grep -qF "$needle"; then
    found_disk_fetches=$((found_disk_fetches + 1))
    echo "  raw instruction contains forbidden disk-fetch: '$needle'" >&2
  fi
  if printf '%s' "$SUBSTITUTED" | grep -qF "$needle"; then
    found_disk_fetches=$((found_disk_fetches + 1))
    echo "  substituted instruction contains forbidden disk-fetch: '$needle'" >&2
  fi
done
if [[ "$found_disk_fetches" -eq 0 ]]; then
  ok "(h) SC-G-1: zero in-step disk-fetch sub-commands (shelf-counter.sh read + jq write-issue-note-result.json)"
else
  nok "(h) SC-G-1 violation: $found_disk_fetches forbidden disk-fetch references in instruction body"
fi

# -----------------------------------------------------------------------------
# Bonus assertion: the bg sub-agent prompt's `{{SHELF_DIR}}` references
# substitute correctly (the bg sub-agent prompt is a heredoc inside the
# foreground instruction, so substitution applies to it too).
# -----------------------------------------------------------------------------
if [[ "$SUBSTITUTED" == *"${TMP}/.shelf-fake/scripts/step-dispatch-background-sync.sh"* ]]; then
  ok "(bonus) {{SHELF_DIR}} substituted in bg sub-agent prompt body"
else
  nok "(bonus) {{SHELF_DIR}} did not substitute in bg sub-agent prompt body"
fi

echo
echo "kiln-report-issue-inputs-resolved: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
