# Feature Specification: Wheel Step Input/Output Schema (`context_from` Rework)

**Feature Branch**: `build/wheel-step-input-output-schema-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-wheel-step-input-output-schema/PRD.md`

## Overview

Wheel today exposes only file *pointers* between steps: a downstream step's `context_from:` produces a "## Context from Previous Steps" footer that lists the upstream step's output **path**, not its **values**. Agents compensate with `jq -r` / `cat` / `grep` boilerplate inside their own instruction text, paying a Bash permission prompt + token cost + wall-clock tax per upstream consumer. The live `/kiln:kiln-report-issue` baseline (recorded in PR #163's `.wheel/history/`) shows the `dispatch-background-sync` step alone executing 5 disk fetches just to assemble its prompt.

This feature adds two workflow JSON fields — `inputs:` (declarative pull) and `output_schema:` (declarative push) — plus a hook-time hydration pass in `plugin-wheel/lib/dispatch.sh` that resolves `inputs:` against the current state, config files, and session registry, prepending a `## Resolved Inputs` block to the agent's instruction and substituting `{{VAR}}` placeholders inline. `context_from:` survives only for pure ordering dependencies (the data-passing footer is suppressed when `inputs:` is present). The migration is atomic with the runtime change for `kiln-report-issue.json` (NFR-G-6) — the same shape as cross-plugin-resolver's NFR-F-7.

Five themes, one feature:
- **Theme G1** — Workflow JSON schema additions (FR-G1-1..FR-G1-4)
- **Theme G2** — JSONPath subset grammar (FR-G2-1..FR-G2-5)
- **Theme G3** — Hook-time hydration + tripwire (FR-G3-1..FR-G3-5)
- **Theme G4** — `kiln-report-issue.json` atomic migration (FR-G4-1..FR-G4-5)
- **Theme G5** — `context_from:` narrowing + audit (FR-G5-1..FR-G5-4)

## Spec-phase decision: OQ-G-1 — secret-detection mechanism (Candidate A — allowlist)

The PRD lists three candidates for NFR-G-7's "no secrets in resolved-inputs block" requirement. **This spec selects Candidate A — allowlist of safe config keys, default-deny on unknown.** Rationale:

- **Simplest mechanism that fails closed.** Pattern-based redaction (Candidate C) is brittle — secret keys with sanitized names slip through. Per-input opt-in via frontmatter (Candidate B) puts the security decision on every workflow author and makes it easy to forget. An allowlist makes the secure default explicit at the resolver level and forces an active opt-in to extend it.
- **Bounded surface area.** v1 only needs `$config()` resolution against `.shelf-config` and a small set of project-state files. The allowlist starts small (`shelf_full_sync_counter`, `shelf_full_sync_threshold`, `slug`, `base_path`, project-level non-secret state) and grows by intentional PR.
- **Allowlist lives next to the resolver.** `plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST` (per-file map) — adding a new key is a one-line PR with security review attached. Out-of-allowlist keys hit a loud error: `Workflow '<name>' resolves $config(<file>:<key>) but '<key>' is not in the safe-key allowlist for <file>. Add it to plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST after security review, or use $step()/$.steps.* for non-config values.`
- **Auditability.** A reviewer scanning a workflow JSON can answer "could this leak a secret?" by grep'ing every `$config(...)` token against the allowlist, no per-workflow flag inspection needed.

This mechanism applies ONLY to `$config(<file>:<key>)` resolution — `$.steps.<id>.output.<field>` and `$plugin(<name>)` and `$step(<id>)` are not gated, because their sources don't typically contain secrets (step outputs are wheel-managed; plugin paths are non-secret by definition). The allowlist is mechanism #1; mechanism #2 is the file-format gate (only `.shelf-config` + JSON via `<file>:<jq-path>` are supported in v1 — no `.env` reading at all). The combination is "no secret can be resolved in v1 because (a) the only readable file types don't typically host secrets and (b) any new file/key requires explicit allowlist extension."

## Spec-phase decision: OQ-G-2 — `context_from:` rename to `after:` (DEFER)

The PRD asks whether to rename `context_from:` to `after:` in v1. **Spec defers the rename.** Rationale: the rename is cosmetic and would touch every shipped workflow (audited inventory in research.md §audit-context-from). Keeping `context_from:` as the ordering field with documented narrowed semantics achieves the same clarity goal at zero migration cost. Follow-on PRD may rename if a workflow author trips over the now-misleading name.

## Spec-phase decision: OQ-G-3 — `inputs:` on `parallel:`/`loop:` step types (DEFER)

The PRD asks whether `inputs:` works on parallel/loop steps. **Spec scopes v1 to `agent` step types only.** `command` steps already have access to env vars and don't need an inputs block. `parallel`/`loop`/`teammate`/`team-create` step types are deferred to a follow-on (the resolver primitive is the same; the dispatch wiring differs). Schema validation rejects `inputs:` on non-agent step types with a documented error.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Author declares `inputs:` and the agent receives resolved values (Priority: P1)

A plugin author writing `kiln-report-issue.json`'s `dispatch-background-sync` step adds:

```json
"inputs": {
  "ISSUE_FILE": "$.steps.write-issue-note.output.issue_file",
  "OBSIDIAN_PATH": "$.steps.write-issue-note.output.obsidian_path",
  "CURRENT_COUNTER": "$config(.shelf-config:shelf_full_sync_counter)",
  "THRESHOLD": "$config(.shelf-config:shelf_full_sync_threshold)",
  "SHELF_DIR": "$plugin(shelf)"
}
```

…and rewrites the instruction body with `{{ISSUE_FILE}}`, `{{OBSIDIAN_PATH}}`, etc. At dispatch time, the agent receives a prompt with a `## Resolved Inputs` block listing every value, plus the placeholders substituted inline. The 5 disk-fetch Bash calls in the current instruction text are deleted entirely.

**Why this priority**: This is the headline value. The PRD's Goal #1 ("agent step prompts self-contained") and SC-G-1 (≥3 fewer Bash tool calls) both depend on this story passing.

**Independent Test**: A `/kiln:kiln-test plugin-kiln kiln-report-issue-inputs-resolved` fixture activates the migrated workflow, asserts the agent step's `command_log` length drops to 0 AND the dispatched instruction text contains zero `bash`/`jq`/`cat`/`grep` references in the step body (per recalibrated SC-G-1; see research.md §baseline), and that the resolved-inputs block contains all 5 expected values.

**Acceptance Scenarios**:

1. **Given** the migrated `kiln-report-issue.json` with `inputs:` on `dispatch-background-sync`, **When** the workflow runs, **Then** the agent prompt contains a `## Resolved Inputs` block listing all 5 inputs with their resolved values.
2. **Given** `{{ISSUE_FILE}}` placeholders in the instruction body, **When** the prompt is dispatched, **Then** every `{{VAR}}` is substituted with the resolved value (zero residuals).
3. **Given** the same migrated workflow, **When** the dispatch-background-sync step runs, **Then** its `command_log` length is 0 (per SC-G-1(a)) AND the dispatched instruction text contains zero `jq -r .../shelf-write-issue-note-result.json` references and zero `bash .../shelf-counter.sh read` references (per SC-G-1(b)).

---

### User Story 2 — Resolution failure aborts the step loud (Priority: P1)

A workflow declares `inputs: { FOO: "$.steps.does-not-exist.output.bar" }`. At step dispatch, the resolver fails loud with:

```
Workflow '<name>' step '<step-id>' input 'FOO' references missing upstream output: step 'does-not-exist' has not run or has no output_schema declaration.
```

The state file does not advance. No agent is dispatched. The step is recorded as failed with the error text in the state file's `error` field.

**Why this priority**: P1 because it's the structural answer to NFR-G-2 (silent-failure tripwires) and the lesson from cross-plugin-resolver: silent fallthrough → silent ship. Loud-failure on resolution errors is what makes "resolved-inputs" a contract instead of a hint.

**Independent Test**: A `/kiln:kiln-test plugin-wheel resolve-inputs-missing-step` fixture activates a workflow with a deliberately missing upstream reference. Assert: (a) state file shows the step in failed state, (b) no agent step was dispatched (no `agent_session_id` recorded), (c) stderr contains the documented error text, (d) exit code is non-zero.

**Acceptance Scenarios**:

1. **Given** an `inputs:` entry referencing a step that hasn't run, **When** dispatch resolves the inputs, **Then** the step fails before any agent dispatch with the documented "missing upstream output" error.
2. **Given** an `inputs:` entry referencing a `$config()` key NOT on the allowlist, **When** dispatch resolves, **Then** the step fails with the documented "not in safe-key allowlist" error.
3. **Given** an `inputs:` entry with a malformed JSONPath (e.g. `$.weird.invalid`), **When** dispatch resolves, **Then** the step fails with the documented "unsupported expression" error.
4. **Given** a residual `{{VAR}}` after substitution (input declared but referenced incorrectly), **When** the tripwire scan runs, **Then** the step fails with the documented "residual placeholder" error.

---

### User Story 3 — Allowlist gate refuses unknown config keys (Priority: P1)

A workflow author writes `inputs: { API_KEY: "$config(.shelf-config:openai_api_key)" }`. The resolver's allowlist for `.shelf-config` does NOT contain `openai_api_key`. The step fails loud at dispatch time, no resolved-inputs block is emitted, no agent runs.

**Why this priority**: P1 — security gate. NFR-G-7 mandates default-deny. R-G-3 explicitly flags this as a security risk. This is the structural answer.

**Independent Test**: A `plugin-wheel/tests/resolve-inputs-secret-block.bats` (pure-shell unit test) constructs a workflow with `$config(.shelf-config:openai_api_key)` and asserts the resolver exits 1 with the documented allowlist error. The fixture also includes a positive case (allowed key resolves correctly).

**Acceptance Scenarios**:

1. **Given** an `inputs:` entry with `$config(<file>:<key>)` where `<key>` is NOT in the allowlist, **When** the resolver runs, **Then** it exits 1 with the "not in safe-key allowlist" error and does NOT inline the value.
2. **Given** an `inputs:` entry with `$config(.unknown-config:any-key)` where `<file>` is NOT in the supported file-type list (`.shelf-config` + JSON via `<file>:<jq-path>`), **When** the resolver runs, **Then** it exits 1 with the "unsupported config file" error.
3. **Given** the allowlist source file `plugin-wheel/lib/resolve_inputs.sh`, **When** an auditor inspects it, **Then** every key is annotated with a security comment explaining why it's safe.

---

### User Story 4 — Backward compat for unmigrated workflows (Priority: P2)

The 6 workflows that don't declare `inputs:`/`output_schema:` (`kiln-mistake.json`, `shelf-sync.json`, `shelf-write-issue-note.json`, `shelf-create.json`, `shelf-feedback.json`, `clay-create-repo.json`) continue to behave byte-identically to today. Their `context_from:` footer text, agent prompts, side effects, and state files produce no diff against a pre-PRD snapshot.

**Why this priority**: P2 because it's the do-no-harm guarantee. Same shape as cross-plugin-resolver's User Story 4 (NFR-F-5).

**Independent Test**: A `/kiln:kiln-test plugin-wheel back-compat-no-inputs` fixture activates an unmigrated workflow against post-PRD code, captures the agent prompt + state file, and diffs against a pre-recorded snapshot. Diff must be empty modulo timestamps and run IDs.

**Acceptance Scenarios**:

1. **Given** a workflow with no `inputs:` or `output_schema:` field, **When** it runs against post-PRD code, **Then** the state file's `steps[]` array, the agent prompts, and the side effects are byte-identical to the pre-PRD snapshot.
2. **Given** a workflow using `context_from:` for ordering only, **When** it runs, **Then** the existing "## Context from Previous Steps" footer behavior is preserved exactly (FR-G1-3 narrowed semantics).

---

### User Story 5 — Live-smoke headline metric satisfied (Priority: P1)

After the migration ships, a fresh `/kiln:kiln-report-issue` invocation against the post-PRD code shows: (a) `dispatch-background-sync.command_log` length drops from baseline median 1 → 0, AND (b) the count of disk-fetch sub-commands inside the dispatch step's (formerly batched) bash drops from baseline median 3 → 0. Per-step wall-clock for `dispatch-background-sync` is lower or within +10% of baseline (36s ±3.6s). See `research.md §baseline` for the recalibration rationale.

**Why this priority**: P1 — the PRD's Absolute Must #3 + #6 makes this a hard merge gate. NFR-G-4 + SC-G-1 + SC-G-2 codify the metric. Lesson lifted from `.kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md` — fixtures alone don't catch wiring bugs.

**Independent Test**: The audit step of this pipeline runs `/kiln:kiln-report-issue` live against the post-PRD code, extracts the `dispatch-background-sync` step's `command_log` from `.wheel/history/success/kiln-report-issue-*.json`, and compares the Bash/Read call count against the researcher's baseline TSV.

**Acceptance Scenarios**:

1. **Given** the post-PRD code, **When** `/kiln:kiln-report-issue` runs end-to-end, **Then** the `dispatch-background-sync` step shows ≥3 fewer agent Bash/Read tool calls vs the baseline.
2. **Given** the same run, **When** wall-clock is measured from activation to `dispatch-background-sync` terminal, **Then** it is lower than baseline (or no more than 10% higher — regression by >10% fails the gate).

---

### User Story 6 — Hydration perf gate (Priority: P2)

Hook-time hydration adds ≤100ms per agent step on a step with up to 5 inputs. Measured via `time` in a kiln-test fixture.

**Why this priority**: P2 — quantitative quality gate, not user-visible. But exceeding the gate blocks merge.

**Independent Test**: `plugin-wheel/tests/hydration-perf/run.sh` invokes `_resolve_inputs` against a synthetic state + workflow with 5 inputs (one per resolver type: `$.steps.*`, `$config()`, `$plugin()`, `$step()`, allowlist-passing config). Captures wall-clock via `time` and asserts ≤100ms median over N=10 runs.

**Acceptance Scenarios**:

1. **Given** the hydration perf fixture, **When** it runs, **Then** median resolve time is ≤100ms over 10 runs.
2. **Given** a step with no `inputs:`, **When** dispatch runs, **Then** the resolver phase adds ≤5ms to dispatch time (no-op fast path).

---

## Functional Requirements

### Theme G1 — Workflow JSON schema additions

- **FR-G1-1**: Workflow agent steps gain an optional `inputs:` field — a JSON object mapping `<UPPERCASE_VAR_NAME>` → JSONPath-subset expression string. Var name must match `^[A-Z][A-Z0-9_]*$`.
- **FR-G1-2**: Workflow steps (any type) gain an optional `output_schema:` field — a JSON object describing named fields. Each field is either:
  - A direct JSON path string (`"file": "$.file"`) for JSON outputs, OR
  - An object `{"extract": "regex:<pattern>"}` or `{"extract": "jq:<expr>"}` for text/markdown outputs.
- **FR-G1-3**: When an agent step declares `inputs:`, the auto-appended "## Context from Previous Steps" footer is suppressed. The resolved-inputs block replaces it. When `inputs:` is absent (regardless of `context_from:`), today's footer behavior is preserved (NFR-G-3 backward compat).
- **FR-G1-4**: Schema validation runs at workflow-load time (`plugin-wheel/lib/workflow.sh::workflow_load`):
  - `inputs:` only on `agent` step types (OQ-G-3 deferral) — non-agent steps with `inputs:` fail load with documented error.
  - Each `inputs:` value must be a parseable JSONPath-subset expression (FR-G2-5).
  - Each `output_schema:` extract directive must parse as `regex:<pattern>` or `jq:<expr>`.
  - References to undeclared upstream steps fail load with documented error.
  - `output_schema:` mismatches (referenced field not in declaring step's schema) fail load.

### Theme G2 — JSONPath subset

- **FR-G2-1**: `$.steps.<step-id>.output.<field>` — resolves to a named field of an upstream step's output, per the upstream step's `output_schema:`.
- **FR-G2-2**: `$config(<file>:<key>)` — reads a key from a config file. v1 supports two file forms:
  - `.shelf-config` (flat `key = value` TOML-ish) — uses existing `plugin-shelf/scripts/shelf-counter.sh read` shape (resolver invokes a small bash helper that respects the format).
  - JSON via `<file>:<jq-path>` (e.g. `$config(.kiln/state.json:.foo.bar)`) — resolver passes the path to `jq -r` against the file.
  - All other file types fail with documented "unsupported config file" error.
  - Allowlist gate (per spec-phase decision OQ-G-1) — key must appear in `plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST` for that file.
- **FR-G2-3**: `$plugin(<name>)` — resolves to a plugin's absolute install path. Delegates to `build_session_registry` (cross-plugin-resolver primitive). Plugin must be in `requires_plugins:` of the workflow OR be wheel itself OR be the calling plugin.
- **FR-G2-4**: `$step(<step-id>)` — resolves to the absolute path of an upstream step's output file (escape hatch for cases where the agent really does need the file path, not the data).
- **FR-G2-5**: Anything else fails loud at workflow-load time AND at dispatch time (defense-in-depth, same shape as cross-plugin-resolver's resolve.sh / preprocess.sh dual gate). Documented error: `Workflow '<name>' input '<VAR>' uses unsupported expression: '<expr>'. Supported: $.steps.<id>.output.<field>, $config(<file>:<key>), $plugin(<name>), $step(<id>).`

### Theme G3 — Hook-time hydration

- **FR-G3-1**: At each agent-step dispatch, `plugin-wheel/lib/dispatch.sh` calls `resolve_inputs` (new function in `plugin-wheel/lib/resolve_inputs.sh`) which iterates each `inputs:` entry and resolves it against the current state, config files, and session registry.
- **FR-G3-2**: Resolved values are prepended to the step's instruction text as a `## Resolved Inputs` block:
  ```
  ## Resolved Inputs
  - **ISSUE_FILE**: .kiln/issues/2026-04-25-foo.md
  - **OBSIDIAN_PATH**: @second-brain/projects/.../foo.md
  - **CURRENT_COUNTER**: 3
  - **THRESHOLD**: 10
  - **SHELF_DIR**: /Users/.../plugin-shelf
  ```
  The block is emitted ONLY when `inputs:` is non-empty. The block is the FIRST block of the instruction (above `## Step Instruction`).
- **FR-G3-3**: `{{VAR}}` placeholders in the instruction body are substituted with the resolved values inline. Substitution runs in the same pass as cross-plugin-resolver's `${WHEEL_PLUGIN_<name>}` substitution (in `preprocess.sh::template_workflow_json`'s extension), so authors get a single substitution model.
- **FR-G3-4**: Resolution failures (input refers to a step that didn't run, config key missing, plugin not in registry, allowlist denial, malformed JSONPath) produce a loud error and abort the step. Step is recorded as failed in state. No silent empty-string substitution.
- **FR-G3-5**: Tripwire — after substitution, no `{{VAR}}` placeholders remain in the instruction. Failure → loud error, no agent dispatch. Documented error: `Hydration tripwire fired on step '<step-id>': residual placeholder(s) {{<NAMES>}} remain after substitution. Either declare them in inputs: or remove the placeholder.`

### Theme G4 — `kiln-report-issue.json` migration (atomic)

- **FR-G4-1**: `plugin-kiln/workflows/kiln-report-issue.json` adds `output_schema:` to:
  - `check-existing-issues` (text output → `existing_count: {extract: "regex:^Existing: ([0-9]+)$"}` if useful, OR omit if unused downstream — research §audit decides)
  - `create-issue` (markdown output → `issue_file: {extract: "regex:^\\.kiln/issues/.*\\.md$"}` to capture the `.kiln/issues/<file>.md` line emitted by the step)
  - `write-issue-note` (JSON output `.wheel/outputs/shelf-write-issue-note-result.json` — `issue_file: "$.issue_file"` and `obsidian_path: "$.obsidian_path"` — direct JSON paths, no extract directive needed).
- **FR-G4-2**: The `dispatch-background-sync` step adds `inputs:`:
  ```
  ISSUE_FILE: "$.steps.write-issue-note.output.issue_file"
  OBSIDIAN_PATH: "$.steps.write-issue-note.output.obsidian_path"
  CURRENT_COUNTER: "$config(.shelf-config:shelf_full_sync_counter)"
  THRESHOLD: "$config(.shelf-config:shelf_full_sync_threshold)"
  SHELF_DIR: "$plugin(shelf)"
  ```
- **FR-G4-3**: The `dispatch-background-sync` step's `instruction:` is rewritten:
  - Remove the `bash "${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh" read` invocation (CURRENT_COUNTER + THRESHOLD now from inputs).
  - Remove the `jq -r '.issue_file, .obsidian_path' .wheel/outputs/shelf-write-issue-note-result.json` invocation (ISSUE_FILE + OBSIDIAN_PATH now from inputs).
  - Replace inline references with `{{ISSUE_FILE}}`, `{{CURRENT_COUNTER}}`, etc.
  - Keep the bg-sub-agent spawn block — it's the actual work, not boilerplate.
  - The 5 disk-fetch commands are deleted entirely from the instruction text.
- **FR-G4-4**: The `create-issue` step's `instruction:` is reviewed for similar fetch-elimination opportunities; any values that can be sourced from `$config()` or `$plugin()` move to `inputs:`. Per research §audit-create-issue, the existing instruction has no in-step fetches (it computes everything from the user description), so only `output_schema:` is added — no `inputs:`.
- **FR-G4-5**: Migration commits atomically with the wheel runtime change (NFR-G-6). The single PR contains: the new `resolve_inputs.sh`, the `dispatch.sh` wiring, the `workflow.sh` schema validation extension, AND the `kiln-report-issue.json` edit. No half-state where the workflow declares `inputs:` but the resolver isn't running.

### Theme G5 — `context_from:` narrowing

- **FR-G5-1**: `plugin-wheel/docs/context-from-narrowing.md` (new doc) records: `context_from:` documents pure ordering only. Data-passing has moved to `inputs:`. The legacy "## Context from Previous Steps" footer is preserved when `inputs:` is absent (back-compat).
- **FR-G5-2**: `context_from:` continues to gate step ordering byte-identically to today (no behavior change for non-data dependencies). The wait-on-step semantics in `dispatch.sh` are not touched.
- **FR-G5-3**: Audit pass (research.md §audit-context-from) classifies all shipped workflows' `context_from:` uses:
  - **Pure ordering** (keep): no agent fetch boilerplate references the upstream output.
  - **Data passing** (migrate to `inputs:`): agent instruction contains `jq`/`cat`/`grep` against the upstream output path.
  - The audit lists each workflow + step + classification + follow-on ticket reference.
- **FR-G5-4**: `context_from:` rename to `after:` is **deferred** to a follow-on PRD (per spec-phase decision OQ-G-2).

## Non-Functional Requirements

- **NFR-G-1 (testing — explicit)**: Every FR-G1..G4 lands with at least one test exercising it end-to-end. Substrate: `/kiln:kiln-test` for any FR depending on real agent-session behavior; pure-shell unit tests acceptable for resolver/hydration logic without an LLM in the loop. **Implementers MUST invoke `/kiln:kiln-test <plugin> <fixture>` for each fixture they author and cite the verdict report path (`.kiln/logs/kiln-test-<uuid>.md`) in their friction note before marking their task complete.** Authoring without invocation does not satisfy NFR-G-1.
- **NFR-G-2 (silent-failure tripwires)**: Each documented failure mode (resolution failure, missing upstream output, malformed JSONPath, residual `{{VAR}}` post-substitution, allowlist denial) has a regression test that fails when the failure becomes silent. Lifted from cross-plugin-resolver NFR-F-2.
- **NFR-G-3 (backward compat — strict)**: Workflows without `inputs:` or `output_schema:` behave byte-identically to today. Verified by re-running an unchanged workflow against post-PRD code and diffing the resulting state file + log file against a pre-PRD snapshot. (Same shape as cross-plugin-resolver NFR-F-5.)
- **NFR-G-4 (live-smoke gate — NON-NEGOTIABLE)**: Audit step MUST run a fresh `/kiln:kiln-report-issue` against the post-PRD code and compare the observable agent tool-call count against the researcher's baseline. Audit fixtures alone are not sufficient. Direct lesson from `.kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md`.
- **NFR-G-5 (resolver perf)**: Hook-time hydration adds at most **100ms** per agent step on a step with up to 5 inputs. Measured via `time` in `plugin-wheel/tests/hydration-perf/run.sh`. No-input fast path adds ≤5ms.
- **NFR-G-6 (atomic migration)**: FR-G4's migration of `kiln-report-issue.json` lands in the same commit as the runtime change. CI grep asserts the workflow's `inputs:` field appearance commit ID matches the runtime change commit ID.
- **NFR-G-7 (no PII or secrets in resolved-inputs block)**: Per spec-phase decision OQ-G-1 — Candidate A allowlist. The allowlist lives at `plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST`. v1 ships with these allowlisted keys (all non-secret by inspection):
  - `.shelf-config` keys: `shelf_full_sync_counter`, `shelf_full_sync_threshold`, `slug`, `base_path`, `obsidian_vault_path`
  - JSON files: only via explicit `<file>:<jq-path>` form, no allowlist (the jq path is the gate; secret values would not be referenced via this form by convention).
  - Adding a new key requires editing the file with a security comment justifying inclusion.

## Edge Cases

| Edge case | Behavior |
|---|---|
| `inputs:` declares a var name that doesn't appear as `{{VAR}}` in the instruction body | Resolved-inputs block still emits the value; no error (the block is the canonical record). |
| `{{VAR}}` appears in the instruction body but is not declared in `inputs:` | Tripwire fires (FR-G3-5) — residual placeholder. |
| Upstream step has `output_schema:` declared but the field referenced doesn't exist in the actual output | Fail at extraction time with documented "field 'X' not found in step '<id>' output per its output_schema" error. |
| Upstream step has NO `output_schema:` declared, but downstream `inputs:` references `$.steps.<id>.output.<field>` | Fail at workflow-load time with documented "step '<id>' referenced by input 'VAR' has no output_schema" error. |
| `output_schema:` extract directive `regex:` matches multiple times | First match wins; no error. (Document in extractor contract.) |
| `output_schema:` extract directive `regex:` doesn't match | Fail at extraction time with documented "regex did not match step '<id>' output" error. |
| `$config(<file>:<key>)` where `<file>` doesn't exist | Fail with documented "config file '<file>' not found" error. |
| `$config(.shelf-config:<key>)` where `<key>` is on the allowlist but missing from the file | Fail with documented "config key '<key>' not found in '<file>'" error (NOT silent empty string). |
| `$plugin(<name>)` where `<name>` is not in `requires_plugins:` | Fail at workflow-load time (defense-in-depth — the cross-plugin-resolver pre-flight ALSO catches this). |
| `inputs:` declared on a non-agent step type | Fail at workflow-load time (FR-G1-4). |
| Workflow has both `inputs:` and `context_from:` on the same step | Both honored: `context_from:` for ordering, `inputs:` for data; no footer is emitted (FR-G1-3). |
| Workflow has `context_from:` but no `inputs:` | Today's footer behavior preserved exactly (NFR-G-3). |

## Success Criteria

### Headline (HARD GATE — required to ship)

- **SC-G-1 (recalibrated against research §baseline)**: Post-PRD live `/kiln:kiln-report-issue` smoke shows BOTH:
  - **(a)** `dispatch-background-sync.command_log` length drops from baseline median **1 → 0** (the agent issues zero Bash tool calls inside the step body — all values arrive pre-resolved in the prompt), AND
  - **(b)** the count of disk-fetch sub-commands inside the (now-removed) batched bash drops from baseline median **3 → 0** (audit greps the post-PRD instruction text for `bash`/`jq`/`cat`/`grep` references and asserts they are gone).
  Either condition failing fails the gate. The PRD's original "≥3 fewer Bash/Read tool calls" framing was written pre-FR-E batching; per researcher-baseline `research.md §baseline` the post-FR-E baseline is already at command_log=1, so the recalibrated form measures the same underlying property (no in-step disk fetches) against the actual FR-E batched baseline.
- **SC-G-2**: Post-PRD live smoke shows lower (or within +10%) wall-clock for `dispatch-background-sync` step (baseline median = 36s; tolerance band per researcher-baseline analysis is +3.6s). Total-workflow wall-clock has high variance (105–261s observed) and is NOT used as the gate; dispatch-step wall-clock (lower variance) is.

### Secondary (informational)

- **SC-G-3**: Per-step token usage in the migrated workflow drops measurably (output_tokens for the dispatch-background-sync step's first agent turn).
- **SC-G-4**: Permission prompt count drops by ≥3 (one per eliminated Bash call).
- **SC-G-5**: `context_from:` audit (research.md §audit-context-from) produces a documented inventory; all data-passing uses get a follow-on migration ticket.
- **SC-G-6**: NFR-G-4 satisfied — live-smoke is part of the PR description's verification checklist, run by the auditor before merge.

## Constraints

- **C-G-1 (tech stack)**: Bash 5.x + `jq` + POSIX. No new runtime dependencies.
- **C-G-2 (kiln-test substrate)**: `/kiln:kiln-test` is the verification gate for any test whose claim depends on real agent-session behavior.
- **C-G-3 (atomic migration)**: NFR-G-6.
- **C-G-4 (loud-failure)**: Every documented failure mode aborts the step with a recognizable error string. NO silent empty-string substitution.
