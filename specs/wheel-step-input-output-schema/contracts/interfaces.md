# Interface Contracts: Wheel Step Input/Output Schema

**Constitution Article VII (NON-NEGOTIABLE)**: Every exported function, script entrypoint, and workflow JSON field defined here is the single source of truth. All implementation — including parallel implementer tracks `impl-resolver-hydration` and `impl-schema-migration` — MUST match these signatures exactly. If a signature needs to change, update THIS FILE first, then re-run affected tests.

This document covers six contracts:

1. [JSONPath subset parser — `_parse_jsonpath_expr`](#1-_parse_jsonpath_expr) — FR-G2
2. [Inputs resolver — `resolve_inputs`](#2-resolve_inputs) — FR-G3-1, FR-G3-4
3. [Output-schema extractor — `extract_output_field`](#3-extract_output_field) — FR-G1-2
4. [`{{VAR}}` substitution — `substitute_inputs_into_instruction`](#4-substitute_inputs_into_instruction) — FR-G3-3, FR-G3-5
5. [Workflow-load schema validator — `workflow_validate_inputs_outputs`](#5-workflow_validate_inputs_outputs) — FR-G1-4
6. [Workflow JSON schema additions](#6-workflow-json-schema-additions) — FR-G1-1, FR-G1-2

Plus one supporting data structure:

7. [Allowlist — `CONFIG_KEY_ALLOWLIST`](#7-config_key_allowlist) — NFR-G-7

---

## 1. `_parse_jsonpath_expr`

**File**: `plugin-wheel/lib/resolve_inputs.sh`
**Owners**: `impl-resolver-hydration` track (sole owner)
**Consumed by**: `impl-schema-migration` (sourced from `workflow.sh::workflow_validate_inputs_outputs` for shape-only validation)

### Signature

```bash
# Usage:
#   source plugin-wheel/lib/resolve_inputs.sh
#   if _parse_jsonpath_expr "$expr"; then
#     # Sets these globals on success:
#     # _PARSED_KIND      — one of: dollar_steps | dollar_config | dollar_plugin | dollar_step
#     # _PARSED_ARG1      — first capture group (step-id | file | plugin-name | step-id)
#     # _PARSED_ARG2      — second capture group (field | key) — empty for $plugin/$step
#     :
#   else
#     # _PARSED_ERROR contains the error reason for callers to use in their own error string
#     :
#   fi
#
# Arguments:
#   $1  expr   — the JSONPath subset expression string to parse
#
# Globals set on success (exit 0):
#   _PARSED_KIND       string — one of dollar_steps, dollar_config, dollar_plugin, dollar_step
#   _PARSED_ARG1       string — first capture
#   _PARSED_ARG2       string — second capture (empty for plugin/step)
#
# Globals set on failure (exit 1):
#   _PARSED_ERROR      string — short reason ("unsupported expression" | "malformed $config syntax" | ...)
#
# Stdout: empty (silent on stdout in both branches)
# Stderr: empty (callers decide whether to print the error)
# Exit: 0 on parseable expression, 1 otherwise
```

### Grammar (FR-G2-1..FR-G2-5)

| Pattern | KIND | ARG1 | ARG2 |
|---|---|---|---|
| `^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$` | `dollar_steps` | step-id | field |
| `^\$config\(([^:)]+):([^)]+)\)$` | `dollar_config` | file | key |
| `^\$plugin\(([A-Za-z0-9_-]+)\)$` | `dollar_plugin` | plugin-name | (empty) |
| `^\$step\(([A-Za-z0-9_-]+)\)$` | `dollar_step` | step-id | (empty) |
| anything else | (no kind set) | — | — |

### Invariants

- **I-PJ-1**: Pure function — no I/O, no side effects, no global state mutation beyond the documented `_PARSED_*` globals.
- **I-PJ-2**: Idempotent — calling twice on the same input sets the same globals.
- **I-PJ-3**: Single source of truth for the grammar. `workflow.sh::workflow_validate_inputs_outputs` MUST source `resolve_inputs.sh` and call this function — it MUST NOT reimplement the grammar.

---

## 2. `resolve_inputs`

**File**: `plugin-wheel/lib/resolve_inputs.sh`
**Owners**: `impl-resolver-hydration` track (sole owner)
**Consumed by**: `dispatch.sh::_dispatch_agent_step`

### Signature

```bash
# Usage:
#   source plugin-wheel/lib/resolve_inputs.sh
#   resolved_map=$(resolve_inputs "$step_json" "$state_json" "$workflow_json" "$registry_json")
#
# Arguments:
#   $1  step_json       — single-line JSON, the step object from workflow.steps[]
#   $2  state_json      — single-line JSON, the parent workflow state file contents
#   $3  workflow_json   — single-line JSON, the templated workflow (output of preprocess.sh)
#   $4  registry_json   — single-line JSON, the output of build_session_registry
#
# Environment: NONE consumed.
#
# Stdout (on exit 0):
#   Single-line JSON object: { "<VAR_NAME>": "<resolved-value>", ... }
#   Empty object {} if step.inputs is absent or empty (no-op fast path).
#
# Stderr (on exit 1):
#   ONE line matching one of the documented error shapes:
#
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' references missing upstream output: step '<id>' has not run or has no output_schema declaration.
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' uses unsupported expression: '<expr>'. Supported: $.steps.<id>.output.<field>, $config(<file>:<key>), $plugin(<name>), $step(<id>).
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' resolves $config(<file>:<key>) but '<key>' is not in the safe-key allowlist for <file>. Add it to plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST after security review, or use $step()/$.steps.* for non-config values.
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' resolves $config(<file>:<key>) but config file '<file>' not found.
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' resolves $config(<file>:<key>) but key '<key>' not found in '<file>'.
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' resolves $plugin(<name>) but '<name>' is not in this session's registry.
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' resolves regex extractor against step '<id>' output but pattern did not match.
#     Workflow '<wf-name>' step '<step-id>' input '<VAR>' references field '<field>' of step '<id>' but '<field>' is not in that step's output_schema.
#
# Exit codes:
#   0  — all inputs resolved; resolved_map JSON on stdout
#   1  — at least one input failed to resolve; documented error on stderr; caller MUST NOT proceed to dispatch
```

### Invariants

- **I-RI-1**: NEVER mutates state. NEVER writes to `.wheel/state/`. Pure resolution.
- **I-RI-2**: Atomic — either all inputs resolve successfully or the function exits 1 on the first failure. No partial map output on failure.
- **I-RI-3**: Output is single-line JSON, jq-parseable. Multi-line is forbidden (breaks downstream `substitute_inputs_into_instruction`).
- **I-RI-4**: Allowlist gate is mandatory for ALL `$config()` resolutions. Unknown keys hit the documented error before any file read.
- **I-RI-5**: NFR-G-5 perf — when `step.inputs` is empty `{}`, function MUST return `{}` in ≤5ms (no-op fast path). Standard 5-input case ≤100ms.

### Behavior on edge cases

| Edge case | Behavior |
|---|---|
| `step.inputs` absent or `{}` | Return `{}` on stdout, exit 0 (fast path) |
| Var name not matching `^[A-Z][A-Z0-9_]*$` | Already caught at workflow_load; runtime treats as parser error |
| Resolved value contains JSON-special chars | Properly jq-encoded in output map |
| Same `$.steps.<id>.output.<field>` referenced by multiple inputs | Resolved once, cached per call |

---

## 3. `extract_output_field`

**File**: `plugin-wheel/lib/resolve_inputs.sh`
**Owners**: `impl-resolver-hydration` track (sole owner)
**Consumed by**: `resolve_inputs` (called for each `$.steps.<id>.output.<field>` resolution)

### Signature

```bash
# Usage:
#   value=$(extract_output_field "$upstream_output" "$output_schema_json" "$field_name")
#
# Arguments:
#   $1  upstream_output         — string, raw output of the upstream step (text or JSON)
#   $2  output_schema_json      — single-line JSON, the upstream step's output_schema field
#   $3  field_name              — string, the field to extract per the schema
#
# Stdout (on exit 0):
#   The extracted value as a string.
#
# Stderr (on exit 1):
#   One of the documented FR-G2 / FR-G1-2 error strings (regex did not match; jq failed; field absent).
#
# Exit:
#   0 — extraction succeeded
#   1 — extraction failed
```

### Extractor types (FR-G1-2)

| `output_schema[field]` shape | Extractor |
|---|---|
| `"$.foo.bar"` (string starting with `$.`) | Treats `upstream_output` as JSON; runs `jq -r '.foo.bar'`. |
| `{"extract": "regex:<pattern>"}` | Treats `upstream_output` as text; runs grep -oE; first match wins; capture group 1 returned if pattern has one, else whole match. |
| `{"extract": "jq:<expr>"}` | Treats `upstream_output` as JSON; runs `jq -r '<expr>'`. |
| Anything else | Fails at workflow-load time (FR-G1-4). |

### Invariants

- **I-EX-1**: Pure function — no state mutation.
- **I-EX-2**: Empty match for regex is a hard failure, not silent empty string (NFR-G-2).
- **I-EX-3**: jq parse failure on the upstream output is a hard failure with the jq error inlined into the documented error text.

---

## 4. `substitute_inputs_into_instruction`

**File**: `plugin-wheel/lib/preprocess.sh` (extension to existing `template_workflow_json` family)
**Owners**: `impl-resolver-hydration` track (sole owner)
**Consumed by**: `dispatch.sh::_dispatch_agent_step` (after `resolve_inputs` returns the resolved map)

### Signature

```bash
# Usage:
#   substituted=$(substitute_inputs_into_instruction "$instruction" "$resolved_map_json" "$step_id")
#
# Arguments:
#   $1  instruction         — string, the agent step's instruction text (post-template_workflow_json)
#   $2  resolved_map_json   — single-line JSON, the output of resolve_inputs
#   $3  step_id             — string, the step id (used in tripwire error text)
#
# Stdout (on exit 0):
#   The instruction text with every {{VAR}} replaced by the resolved value.
#
# Stderr (on exit 1):
#   Hydration tripwire fired on step '<step-id>': residual placeholder(s) {{<NAMES>}} remain after substitution. Either declare them in inputs: or remove the placeholder.
#
# Exit:
#   0 — substitution complete, no residual {{VAR}} remains
#   1 — tripwire fired (FR-G3-5)
```

### Tripwire pattern

`\{\{[A-Z][A-Z0-9_]*\}\}` — narrowed to uppercase-leading. Generic `{{...}}` (lowercase, mixed-case) is invisible to this scan, so other templating uses don't false-positive.

### Invariants

- **I-SI-1**: Substitution is whole-match — `{{ISSUE_FILE}}` substitutes; `{{ISSUE_FILE_X}}` does not collide (it's a different name).
- **I-SI-2**: Tripwire scans AFTER substitution. The scan is the canonical proof that resolved-inputs were enough.
- **I-SI-3**: Idempotent on already-substituted text — a second call finds no `{{VAR}}` patterns and returns the input unchanged.

---

## 5. `workflow_validate_inputs_outputs`

**File**: `plugin-wheel/lib/workflow.sh`
**Owners**: `impl-schema-migration` track (sole owner)
**Consumed by**: `workflow_load` (called after existing validators)

### Signature

```bash
# Usage:
#   workflow_validate_inputs_outputs "$workflow_json" || return 1
#
# Arguments:
#   $1  workflow_json   — string, validated JSON (post-jq-empty + post-required-fields validation)
#
# Environment: sources plugin-wheel/lib/resolve_inputs.sh for _parse_jsonpath_expr.
#
# Stdout: empty
# Stderr (on exit 1): single line per first offending issue, matching one of:
#
#     Workflow '<name>' step '<id>' (type: <type>) declares 'inputs:' but type 'agent' is required.
#     Workflow '<name>' step '<id>' input '<VAR>' has invalid var name (must match ^[A-Z][A-Z0-9_]*$).
#     Workflow '<name>' step '<id>' input '<VAR>' uses unsupported expression: '<expr>'. Supported: $.steps.<id>.output.<field>, $config(<file>:<key>), $plugin(<name>), $step(<id>).
#     Workflow '<name>' step '<id>' input '<VAR>' references upstream step '<other-id>' that does not appear before this step.
#     Workflow '<name>' step '<id>' input '<VAR>' references field '<field>' of step '<other-id>' but that step has no output_schema declaration.
#     Workflow '<name>' step '<id>' input '<VAR>' references field '<field>' of step '<other-id>' but that field is not declared in that step's output_schema.
#     Workflow '<name>' step '<id>' output_schema field '<field>' has malformed extract directive: '<directive>'. Supported: regex:<pattern>, jq:<expr>, or a JSON-path string starting with $.
#     Workflow '<name>' step '<id>' input '<VAR>' resolves $plugin('<name>') but '<name>' is not in requires_plugins (declare it explicitly).
#
# Exit:
#   0  — all inputs/output_schema declarations are well-formed
#   1  — first failure documented; caller (workflow_load) returns 1
```

### Validation rules (FR-G1-4)

1. `inputs:` only appears on `agent` step types. Other types fail.
2. Each var name matches `^[A-Z][A-Z0-9_]*$`.
3. Each input expression parses via `_parse_jsonpath_expr` (errors mirror runtime errors byte-for-byte per the cross-plugin-resolver dual-gate pattern).
4. `$.steps.<id>.output.<field>` references must be to a step appearing BEFORE this step in `.steps[]`.
5. The referenced upstream step MUST declare `output_schema`, AND the referenced `<field>` MUST appear in that schema.
6. `$plugin(<name>)` references must have `<name>` in the workflow's `requires_plugins:` (or be wheel itself, or the calling plugin — wheel is implicit).
7. Each `output_schema:` field's extract directive parses (regex / jq / JSON path).
8. `$config()` references are NOT allowlist-checked at workflow-load time — that's runtime resolver behavior. Workflow-load only enforces shape.

### Invariants

- **I-WV-1**: Defense-in-depth dual-gate per cross-plugin-resolver pattern: workflow-load catches static issues; runtime `resolve_inputs` catches dynamic issues. Both error strings come from the same source-of-truth functions to avoid drift.
- **I-WV-2**: Pure shape check — does not read config files, does not query the registry. (Those are runtime concerns.)
- **I-WV-3**: First-error-wins. Multiple errors in one workflow surface one error message (the first); fix-and-rerun cycle is explicit.

---

## 6. Workflow JSON schema additions

**File**: `plugin-wheel/docs/workflow-schema.md` (canonical reference; updated in this PR) and consumed by `workflow.sh::workflow_validate_inputs_outputs`.
**Owners**: `impl-schema-migration` track.

### `inputs:` field (FR-G1-1)

- **Optional** on `agent` step types. Forbidden on all other step types.
- **Type**: JSON object.
- **Keys**: `^[A-Z][A-Z0-9_]*$` (uppercase var names).
- **Values**: JSONPath-subset expression strings per FR-G2.

```json
{
  "id": "dispatch-background-sync",
  "type": "agent",
  "inputs": {
    "ISSUE_FILE":        "$.steps.write-issue-note.output.issue_file",
    "OBSIDIAN_PATH":     "$.steps.write-issue-note.output.obsidian_path",
    "CURRENT_COUNTER":   "$config(.shelf-config:shelf_full_sync_counter)",
    "THRESHOLD":         "$config(.shelf-config:shelf_full_sync_threshold)",
    "SHELF_DIR":         "$plugin(shelf)"
  },
  "instruction": "...{{ISSUE_FILE}}...{{CURRENT_COUNTER}}...",
  "context_from": ["create-issue", "write-issue-note"],
  "output": ".wheel/outputs/dispatch-background-sync.txt",
  "terminal": true
}
```

### `output_schema:` field (FR-G1-2)

- **Optional** on any step type.
- **Type**: JSON object.
- **Keys**: arbitrary field names (no charset restriction).
- **Values**: either a string (JSON-path starting with `$.`) for direct JSON extraction, OR an object `{"extract": "regex:<pattern>"}` or `{"extract": "jq:<expr>"}` for text extraction.

```json
{
  "id": "create-issue",
  "type": "agent",
  "output_schema": {
    "issue_file": {"extract": "regex:^\\.kiln/issues/.*\\.md$"}
  },
  ...
}
```

```json
{
  "id": "write-issue-note",
  "type": "workflow",
  "workflow": "shelf:shelf-write-issue-note",
  "output_schema": {
    "issue_file":    "$.issue_file",
    "obsidian_path": "$.obsidian_path"
  }
}
```

### `context_from:` (narrowed semantics — FR-G1-3, FR-G5)

- **Type**: unchanged (JSON array of step IDs).
- **Semantics**: pure ordering only. The data-passing footer is suppressed when the step ALSO declares `inputs:`.
- **Rename to `after:` deferred** (per spec-phase decision OQ-G-2).

### Schema validation timing

Validation runs at workflow-load time (`workflow_load`), AFTER existing validators (branch refs, workflow refs, allow_user_input, requires_plugins). Failure surfaces ONE line on stderr matching the strings in §5 above, exit 1.

---

## 7. `CONFIG_KEY_ALLOWLIST`

**File**: `plugin-wheel/lib/resolve_inputs.sh`
**Owners**: `impl-resolver-hydration` track (sole owner)

### Definition

```bash
# v1 allowlist — every entry MUST have a security-justification comment.
# Adding a new entry requires explicit security review (see NFR-G-7 +
# specs/wheel-step-input-output-schema/spec.md OQ-G-1 decision).
declare -gA CONFIG_KEY_ALLOWLIST=(
  [".shelf-config:shelf_full_sync_counter"]="non-secret integer counter (full-sync cadence state)"
  [".shelf-config:shelf_full_sync_threshold"]="non-secret integer threshold (full-sync cadence config)"
  [".shelf-config:slug"]="non-secret project slug (used in Obsidian path computation)"
  [".shelf-config:base_path"]="non-secret filesystem path (Obsidian vault base)"
  [".shelf-config:obsidian_vault_path"]="non-secret filesystem path (full vault location)"
)
```

### JSON file form (`<file>:<jq-path>`)

NOT allowlisted. The literal jq path appears in the workflow JSON, which is reviewable. Adding a JSON-file allowlist is a v2 candidate if a workflow ends up referencing secret-shaped fields by jq path.

### Invariants

- **I-AL-1**: Default-deny. An unknown `<file>:<key>` combination triggers the documented allowlist-denial error.
- **I-AL-2**: The allowlist is the v1 secret-leak gate. Pattern-based redaction (Candidate C) and per-input frontmatter opt-in (Candidate B) are explicitly NOT used.
- **I-AL-3**: Modifying the allowlist requires a code review with the `security` label per the project's review policy.

---

## Cross-track dependencies

- `impl-schema-migration` SOURCES `_parse_jsonpath_expr` from `resolve_inputs.sh`. **`impl-resolver-hydration` MUST land its parser FIRST** (Phase 2.A before Phase 2.B). Tasks.md flags this as `[DEP impl-resolver-hydration <task-id>]`.
- `impl-schema-migration`'s atomic-migration commit (NFR-G-6) requires `impl-resolver-hydration`'s dispatch wiring to be in place; both land in the same commit. Tasks.md sequences Phase 4 to gate on Phase 3.
