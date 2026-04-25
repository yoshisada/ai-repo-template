# Implementation Plan: Wheel Step Input/Output Schema

**Spec**: [spec.md](./spec.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md) | **Tasks**: [tasks.md](./tasks.md)
**PRD**: [../../docs/features/2026-04-25-wheel-step-input-output-schema/PRD.md](../../docs/features/2026-04-25-wheel-step-input-output-schema/PRD.md)

## §1 — Architecture overview

One new bash library + edits to three existing libraries under `plugin-wheel/lib/`:

```
plugin-wheel/lib/
  resolve_inputs.sh   NEW   — resolve_inputs(), extract_output_field(), CONFIG_KEY_ALLOWLIST (Theme G2 + G3 + OQ-G-1)
  preprocess.sh       EDIT  — extend template_workflow_json() to also substitute {{VAR}} placeholders against resolved inputs (Theme G3)
  workflow.sh         EDIT  — workflow_load() gains schema validation for inputs: + output_schema: (Theme G1 / FR-G1-4)
  context.sh          EDIT  — context_build() emits the "## Resolved Inputs" block + suppresses the legacy footer when inputs: is present (FR-G1-3, FR-G3-2)
  dispatch.sh         EDIT  — at agent-step dispatch, call resolve_inputs() before context_build() and pass the resolved map (Theme G3 / FR-G3-1)
```

Two test homes:

```
plugin-wheel/tests/                              — pure-shell unit tests (no LLM)
  resolve-inputs-grammar/                         — JSONPath subset parser (FR-G2-1..FR-G2-5)
  resolve-inputs-allowlist/                       — Candidate A allowlist gate (NFR-G-7)
  resolve-inputs-error-shapes/                    — every documented failure mode's exact stderr string (NFR-G-2)
  hydration-tripwire/                             — residual {{VAR}} detection (FR-G3-5)
  hydration-perf/                                 — ≤100ms / ≤5ms perf gate (NFR-G-5)
  output-schema-extract-regex/                    — regex extractor (FR-G1-2)
  output-schema-extract-jq/                       — jq extractor (FR-G1-2)
  back-compat-no-inputs/                          — byte-identical for unmigrated workflows (NFR-G-3)

plugin-kiln/tests/                                — /kiln:kiln-test substrate (real LLM-driven)
  kiln-report-issue-inputs-resolved/              — User Story 1 happy path (atomic migration verification)
  resolve-inputs-missing-step/                    — User Story 2 P1 — fail-loud on missing upstream
```

Single workflow JSON migrated:

```
plugin-kiln/workflows/kiln-report-issue.json   EDIT (FR-G4)
```

## §2 — Phasing

### Phase 1 — Setup (shared, all tracks observe)

- Read `.specify/memory/constitution.md`, `spec.md`, this plan, `contracts/interfaces.md`, `research.md` (researcher-baseline produces it).
- Stub `agent-notes/{specifier,researcher-baseline,impl-resolver-hydration,impl-schema-migration,audit-compliance,retrospective}.md`.
- Confirm `bash 5.x`, `jq`, `python3` available (existing wheel runtime deps; no new install).

### Phase 2 — Foundational (parallelizable across tracks)

**Phase 2.A** (impl-resolver-hydration): Pure-shell parser + resolver in `plugin-wheel/lib/resolve_inputs.sh`. Implements `_parse_jsonpath_expr`, `_resolve_dollar_steps`, `_resolve_dollar_config`, `_resolve_dollar_plugin`, `_resolve_dollar_step`. Allowlist defined as `declare -A CONFIG_KEY_ALLOWLIST`. Pure-shell `.bats`-shape `run.sh` tests under `plugin-wheel/tests/resolve-inputs-*` validate without a live state file or LLM.

**Phase 2.B** (impl-schema-migration): Workflow-load schema validation in `workflow.sh::workflow_validate_inputs_outputs`. Pure shape checks: `inputs:` only on agent steps; var name regex; expression parseability (calls into `_parse_jsonpath_expr` from resolver); `output_schema:` directive parseability. Validation byte-error-text matches the resolver's runtime errors (defense-in-depth, lifted from cross-plugin-resolver's workflow.sh ↔ resolve.sh dual-gate pattern).

These two sub-phases are parallelizable — they don't share files. Phase 2.A's `_parse_jsonpath_expr` is sourced by Phase 2.B for shape validation, so impl-resolver-hydration commits its parser FIRST, then impl-schema-migration consumes it.

### Phase 3 — Theme G3 hydration wired into dispatch (impl-resolver-hydration)

- `dispatch.sh::_dispatch_agent_step` (or the equivalent function — see existing dispatch.sh) calls `resolve_inputs "$step_json" "$state_json" "$workflow_json" "$registry_json"` BEFORE `context_build`.
- Resolved map flows into `context.sh::context_build` as a 4th argument; `context_build` emits the `## Resolved Inputs` block when the map is non-empty AND suppresses the legacy footer when `inputs:` is present on the step.
- `preprocess.sh::template_workflow_json` extends to also substitute `{{VAR}}` against the resolved map (the existing `${WHEEL_PLUGIN_<name>}` substitution path is unchanged; `{{VAR}}` is a sibling pattern in the same python3 invocation).
- Tripwire (FR-G3-5) — narrowed pattern `\{\{[A-Z][A-Z0-9_]*\}\}` post-substitution; on match, fail loud, abort dispatch.
- Two `/kiln:kiln-test` fixtures land here: `kiln-report-issue-inputs-resolved/` (happy path, but ALSO covers User Story 5 because it's the migrated workflow), `resolve-inputs-missing-step/` (fail-loud on missing upstream).

### Phase 4 — Theme G1 schema validation + Theme G4 atomic migration (impl-schema-migration)

- `workflow.sh::workflow_load` extended: shape-only validation for `inputs:` + `output_schema:` per FR-G1-4 (uses `_parse_jsonpath_expr` from resolver for expression parseability).
- `kiln-report-issue.json` edited per FR-G4-1..FR-G4-4.
- `output_schema:` introduced on three steps (`check-existing-issues`, `create-issue`, `write-issue-note`).
- `dispatch-background-sync` step gains `inputs:` block; instruction body rewritten with `{{VAR}}` placeholders; the 5 in-step disk fetches are deleted.
- The atomic-commit invariant (NFR-G-6) is enforced by impl-schema-migration: the workflow JSON edit lands IN THE SAME COMMIT as the runtime change. Phase 4 is gated on Phase 3 completing; the audit step verifies `git log -1 --name-only` for the merge commit shows BOTH `plugin-wheel/lib/resolve_inputs.sh` AND `plugin-kiln/workflows/kiln-report-issue.json`.

### Phase 5 — Audit + live-smoke headline metric (audit-compliance)

- Audit verifies every FR-G1..G4 has ≥1 fixture with a passing kiln-test verdict report cited in implementer friction notes (NFR-G-1 + Absolute Must #2).
- Audit runs the live `/kiln:kiln-report-issue` smoke against post-PRD code, captures `command_log`, compares Bash/Read count against baseline TSV. SC-G-1 + SC-G-2 must pass (NFR-G-4 NON-NEGOTIABLE).
- Audit greps `.wheel/history/success/*.json` for residual `{{VAR}}` patterns post-PRD — must be zero.
- Audit verifies `git show <merge>` contains both runtime + workflow JSON edits (NFR-G-6).

### Phase 6 — Retrospective

- Retrospective analyzes whether the live-smoke discipline (introduced as NFR-G-4 in direct response to the cross-plugin-resolver mistake) actually caught issues, or became a checkbox.
- Reviews implementer friction notes for prompt/communication improvements; routes findings to GitHub `label:retrospective` issues for `/kiln:kiln-pi-apply` consumption.

## §3 — Implementation notes

### §3.A — JSONPath subset parser

The grammar is deliberately tiny. A regex-based dispatcher at the front:

```
^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$       → $.steps  resolver
^\$config\(([^:)]+):([^)]+)\)$                                 → $config  resolver
^\$plugin\(([A-Za-z0-9_-]+)\)$                                  → $plugin  resolver
^\$step\(([A-Za-z0-9_-]+)\)$                                    → $step    resolver
```

Anything else returns "unsupported expression" with the offending var name + expression in the error text. The parser is shared between `workflow.sh` (load-time shape validation) and `resolve_inputs.sh` (runtime resolution) — same function, same error strings.

### §3.B — `output_schema:` extraction

Two extractor types:

- **Direct JSON path** (`"file": "$.file"`): the upstream output is parsed as JSON; the path is fed to `jq -r`. Matches the existing `shelf-write-issue-note-result.json` shape.
- **Extract directive** (`"file": {"extract": "regex:^.../path/(.*)$"}`): the upstream output is read as text; the regex (or jq expression) extracts the field. Used for markdown step outputs where structured JSON isn't available.

When an upstream step has `output_schema:` declared, downstream `inputs:` referencing fields not in the schema fails at WORKFLOW-LOAD time (defense-in-depth; can't dispatch a step that's already known to be unsatisfiable). When the upstream has NO `output_schema:`, downstream `$.steps.<id>.output.<field>` references fail at workflow-load with "step '<id>' has no output_schema" error.

### §3.C — Allowlist mechanism

Per spec-phase decision OQ-G-1 (Candidate A). Implemented as a bash associative array in `resolve_inputs.sh`:

```bash
declare -gA CONFIG_KEY_ALLOWLIST=(
  [".shelf-config:shelf_full_sync_counter"]="non-secret integer counter"
  [".shelf-config:shelf_full_sync_threshold"]="non-secret integer threshold"
  [".shelf-config:slug"]="non-secret project slug"
  [".shelf-config:base_path"]="non-secret filesystem path"
  [".shelf-config:obsidian_vault_path"]="non-secret filesystem path"
)
```

JSON file form (`<file>:<jq-path>`) is NOT allowlisted — the jq path itself is the gate (the workflow author writes the literal path, so a reviewer can grep the jq paths used across all workflows). Adding a JSON-file allowlist is a v2 candidate if a workflow ends up referencing secret-shaped fields by jq path.

### §3.D — Tripwire pattern

Narrowed pattern: `\{\{[A-Z][A-Z0-9_]*\}\}`. Generic `{{...}}` (e.g. mustache templates) doesn't match because the gate is uppercase-leading. False positives on body text containing `{{FOO}}` literally (e.g. workflow author documenting the syntax) are NOT supported in v1 — the tripwire is unconditional. If a future workflow needs to embed literal `{{FOO}}` for documentation, the escape grammar follows preprocess.sh's `$${...}` precedent.

### §3.E — Atomic migration enforcement

NFR-G-6 says the workflow JSON edit lands in the same commit as the runtime. CI enforcement:

```yaml
- name: Verify atomic migration (NFR-G-6)
  run: |
    # The merge commit (or the squashed PR commit) MUST touch BOTH
    # plugin-wheel/lib/resolve_inputs.sh AND plugin-kiln/workflows/kiln-report-issue.json.
    git log -1 --name-only HEAD | grep -q 'plugin-wheel/lib/resolve_inputs.sh' || exit 1
    git log -1 --name-only HEAD | grep -q 'plugin-kiln/workflows/kiln-report-issue.json' || exit 1
```

This guard lives in `.github/workflows/wheel-tests.yml` alongside the existing SC-007 + SC-F-6 grep guards.

### §3.F — Perf budget

NFR-G-5 hooks: ≤100ms / ≤5ms. The dominant cost in `resolve_inputs` is `jq` invocations (one per `$.steps.*` resolution; one per `$config(<file>:<jq-path>)` resolution). With 5 inputs each invoking `jq` once, the budget is 20ms per `jq` start-up — well above measured `jq` cold-start (~5–10ms on macOS). No-op fast path simply checks `inputs == "{}"` at the top and returns immediately.

## §4 — Tracking matrix (FR → file → test)

| FR | File(s) | Test |
|---|---|---|
| FR-G1-1 (`inputs:` field) | `workflow.sh`, `resolve_inputs.sh` | `resolve-inputs-grammar/` |
| FR-G1-2 (`output_schema:` field) | `workflow.sh`, `resolve_inputs.sh` | `output-schema-extract-{regex,jq}/` |
| FR-G1-3 (footer suppression) | `context.sh` | `back-compat-no-inputs/` (negative) + `kiln-report-issue-inputs-resolved/` (positive) |
| FR-G1-4 (load-time validation) | `workflow.sh` | `resolve-inputs-grammar/` (load form) |
| FR-G2-1 (`$.steps.*`) | `resolve_inputs.sh` | `resolve-inputs-grammar/` |
| FR-G2-2 (`$config()`) | `resolve_inputs.sh` | `resolve-inputs-grammar/` + `resolve-inputs-allowlist/` |
| FR-G2-3 (`$plugin()`) | `resolve_inputs.sh` | `resolve-inputs-grammar/` |
| FR-G2-4 (`$step()`) | `resolve_inputs.sh` | `resolve-inputs-grammar/` |
| FR-G2-5 (anything else fails) | `resolve_inputs.sh`, `workflow.sh` | `resolve-inputs-error-shapes/` |
| FR-G3-1 (hydration in dispatch) | `dispatch.sh` | `kiln-report-issue-inputs-resolved/` |
| FR-G3-2 (resolved-inputs block) | `context.sh` | `kiln-report-issue-inputs-resolved/` |
| FR-G3-3 (`{{VAR}}` substitution) | `preprocess.sh` | `resolve-inputs-grammar/` (substitution form) |
| FR-G3-4 (resolution failure abort) | `resolve_inputs.sh`, `dispatch.sh` | `resolve-inputs-missing-step/` + `resolve-inputs-error-shapes/` |
| FR-G3-5 (residual `{{VAR}}` tripwire) | `preprocess.sh` | `hydration-tripwire/` |
| FR-G4-1..G4-5 (atomic migration) | `kiln-report-issue.json` | `kiln-report-issue-inputs-resolved/` + CI atomic-commit guard |
| FR-G5-1..G5-3 (audit + narrowing doc) | `plugin-wheel/docs/context-from-narrowing.md`, `research.md` §audit | (researcher-baseline produces audit) |
| NFR-G-1 (test substrate) | All | All fixtures cited in friction notes |
| NFR-G-2 (silent-failure tripwires) | All | `resolve-inputs-error-shapes/` (mutation tripwire per FR-F2 pattern) |
| NFR-G-3 (back-compat) | `context.sh` | `back-compat-no-inputs/` |
| NFR-G-4 (live-smoke) | (audit phase) | Audit step's live `/kiln:kiln-report-issue` |
| NFR-G-5 (perf) | `resolve_inputs.sh` | `hydration-perf/` |
| NFR-G-6 (atomic commit) | (CI) | CI guard in wheel-tests.yml |
| NFR-G-7 (allowlist) | `resolve_inputs.sh` | `resolve-inputs-allowlist/` |
