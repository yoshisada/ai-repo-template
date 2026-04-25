# Wheel Workflow JSON Schema

**Status**: Canonical reference for the workflow JSON shape consumed by `plugin-wheel/lib/workflow.sh::workflow_load`.
**Validator**: `plugin-wheel/lib/workflow.sh` (load-time shape checks); `plugin-wheel/lib/resolve_inputs.sh` (runtime resolution + dual-gate error parity).
**Spec**: `specs/wheel-step-input-output-schema/` (FR-G1, FR-G2, FR-G5).

This doc covers ONLY the fields added/narrowed by the wheel-step-input-output-schema PRD. For the full historical schema (steps, branches, sub-workflows, teams, etc.) see existing field comments in `plugin-wheel/lib/workflow.sh`.

---

## `inputs:` (FR-G1-1)

**Optional** field on `agent` step types. **Forbidden** on every other step type — `command`, `workflow`, `branch`, `loop`, `parallel`, `teammate`, `team-create`, `team-wait`, `team-delete`. (Deferred to a follow-on per OQ-G-3 of the spec.)

**Type**: JSON object.

**Keys**: must match `^[A-Z][A-Z0-9_]*$` (uppercase var names — uppercase-leading, alphanumeric + underscore).

**Values**: JSONPath-subset expression strings. Four supported forms (per `_parse_jsonpath_expr` in `resolve_inputs.sh`):

| Form | Resolves to |
|---|---|
| `$.steps.<step-id>.output.<field>` | Named field of an upstream step's output, per the upstream step's `output_schema:`. |
| `$config(<file>:<key>)` | Value from a config file. v1 supports `.shelf-config` (flat `key = value`) and JSON via `<file>:<jq-path>`. Allowlist-gated for `.shelf-config`. |
| `$plugin(<name>)` | Absolute install path of a plugin. Plugin must be in the workflow's `requires_plugins:` (or be wheel itself, or the calling plugin). |
| `$step(<step-id>)` | Absolute path of an upstream step's output file. Escape hatch when the agent really does need the file path, not the data. |

Anything else is rejected at workflow-load time AND at runtime resolution (defense-in-depth, matching the cross-plugin-resolver dual-gate pattern).

**Example**:

```json
{
  "id": "dispatch-background-sync",
  "type": "agent",
  "inputs": {
    "ISSUE_FILE":      "$.steps.write-issue-note.output.issue_file",
    "OBSIDIAN_PATH":   "$.steps.write-issue-note.output.obsidian_path",
    "CURRENT_COUNTER": "$config(.shelf-config:shelf_full_sync_counter)",
    "THRESHOLD":       "$config(.shelf-config:shelf_full_sync_threshold)",
    "SHELF_DIR":       "$plugin(shelf)"
  },
  "instruction": "Dispatch background sync. ISSUE_FILE={{ISSUE_FILE}} ... CURRENT_COUNTER={{CURRENT_COUNTER}} ...",
  "context_from": ["create-issue", "write-issue-note"],
  "output": ".wheel/outputs/dispatch-background-sync.txt",
  "terminal": true
}
```

When `inputs:` is non-empty:

1. The wheel runtime (`plugin-wheel/lib/dispatch.sh`) resolves every entry before agent dispatch.
2. A `## Resolved Inputs` block is prepended to the instruction text (FR-G3-2).
3. Every `{{VAR}}` placeholder in the instruction body is substituted inline (FR-G3-3).
4. The legacy `## Context from Previous Steps` footer is suppressed (FR-G1-3).
5. A tripwire scan after substitution refuses dispatch if any `{{VAR}}` placeholder remains (FR-G3-5).

When `inputs:` is absent (or empty `{}`), runtime behavior is byte-identical to today (NFR-G-3 backward compat).

---

## `output_schema:` (FR-G1-2)

**Optional** field on **any** step type.

**Type**: JSON object.

**Keys**: arbitrary field names (no charset restriction).

**Values**: each field is one of:

| Shape | Behavior |
|---|---|
| `"$.foo.bar"` (string starting with `$.`) | Direct JSON-path extraction. The upstream output is parsed as JSON; the path is fed to `jq -r`. |
| `{"extract": "regex:<pattern>"}` | Text-mode extraction. The upstream output is read as text; first match wins; capture group 1 returned if pattern has one, else whole match. |
| `{"extract": "jq:<expr>"}` | JSON-mode extraction with a jq expression. Treats upstream output as JSON; runs `jq -r '<expr>'`. |

Anything else is rejected at workflow-load time.

**Example — `agent` step with regex extraction**:

```json
{
  "id": "create-issue",
  "type": "agent",
  "output_schema": {
    "issue_file": {"extract": "regex:^\\.kiln/issues/.*\\.md$"}
  }
}
```

**Example — `workflow` step with direct JSON paths** (sub-workflow filename quirk — see `context-from-narrowing.md`):

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

When a downstream `inputs:` references `$.steps.<id>.output.<field>`:

1. The validator (workflow-load time) checks that `<id>` is an earlier step AND that `<field>` is declared in that step's `output_schema:`.
2. The runtime (`extract_output_field` in `resolve_inputs.sh`) reads the output file using the configured extractor.
3. Extraction failure (regex no-match, jq error, missing field) → loud failure with documented error string. No silent empty-string substitution (NFR-G-2).

---

## `context_from:` (narrowed semantics — FR-G1-3, FR-G5-1, FR-G5-2)

**Type**: unchanged (JSON array of step IDs).

**Semantics — narrowed**: pure ordering only. Establishes "step Y must run after step X". The data-passing footer is **suppressed when the step ALSO declares `inputs:`** (FR-G1-3).

**Backward compat — strict**: when `inputs:` is absent, the legacy `## Context from Previous Steps` footer is preserved byte-identically (NFR-G-3).

**Rename to `after:` — deferred** to a follow-on PRD (per OQ-G-2 of `specs/wheel-step-input-output-schema/spec.md`).

See [`context-from-narrowing.md`](./context-from-narrowing.md) for the full migration guide and audit summary.

---

## Validation timing & order

`workflow_load` runs validators in this order (each failing fast):

1. JSON well-formedness (`jq empty`).
2. Required fields (`name`, `steps[]`, each step `id` + `type`).
3. Branch + next + team + loop_from references.
4. Sub-workflow references (recursive).
5. `allow_user_input` permission check.
6. `requires_plugins` shape (FR-F2-3).
7. **`inputs:` + `output_schema:` shape** (FR-G1-4 — added by this PRD): see `workflow_validate_inputs_outputs` in `workflow.sh`.

Failure surfaces ONE error line on stderr matching the documented strings in `contracts/interfaces.md` §5, with exit 1.

### Documented error shapes (workflow-load)

The validator emits one of these strings on the first offending issue:

```
Workflow '<name>' step '<id>' (type: <type>) declares 'inputs:' but type 'agent' is required.
Workflow '<name>' step '<id>' input '<VAR>' has invalid var name (must match ^[A-Z][A-Z0-9_]*$).
Workflow '<name>' step '<id>' input '<VAR>' uses unsupported expression: '<expr>'. Supported: $.steps.<id>.output.<field>, $config(<file>:<key>), $plugin(<name>), $step(<id>).
Workflow '<name>' step '<id>' input '<VAR>' references upstream step '<other-id>' that does not appear before this step.
Workflow '<name>' step '<id>' input '<VAR>' references field '<field>' of step '<other-id>' but that step has no output_schema declaration.
Workflow '<name>' step '<id>' input '<VAR>' references field '<field>' of step '<other-id>' but that field is not declared in that step's output_schema.
Workflow '<name>' step '<id>' output_schema field '<field>' has malformed extract directive: '<directive>'. Supported: regex:<pattern>, jq:<expr>, or a JSON-path string starting with $.
Workflow '<name>' step '<id>' input '<VAR>' resolves $plugin('<name>') but '<name>' is not in requires_plugins (declare it explicitly).
```

Runtime error shapes (resolver-time) are documented in `contracts/interfaces.md` §2 and intentionally mirror the workflow-load shapes byte-for-byte for the dual-gate pattern.

---

## Defense-in-depth dual gate (cross-plugin-resolver pattern)

`workflow.sh::workflow_validate_inputs_outputs` (load-time) and `resolve_inputs.sh::resolve_inputs` + `extract_output_field` (runtime) both validate inputs against the **same grammar** (`_parse_jsonpath_expr`). Errors strings are deliberately identical so the NFR-G-2 silent-failure tripwires (`resolve-inputs-error-shapes` test) keep firing on the documented strings regardless of whether the static or dynamic gate caught the bug.

**Why both?** Some failure modes (e.g. missing config file at runtime, plugin not in session registry) can only be detected dynamically. Other failure modes (e.g. forward-reference to a step that hasn't been declared yet, malformed expression syntax) are best caught at load time before any state is mutated. Mirroring the error strings makes the difference invisible to consumers — same failure, same error text.
