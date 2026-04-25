# Feature Specification: Wheel Typed-Schema Locality (Fail-Fast + Surface-the-Contract)

**Feature Branch**: `build/wheel-typed-schema-locality-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-wheel-typed-schema-locality/PRD.md`
**Builds on**: PR #166 (`specs/wheel-step-input-output-schema/`) — does not block

## Overview

PR #166 shipped typed `inputs:` + `output_schema:` on wheel agent steps. A live `/kiln:kiln-report-issue` smoke (cited in `.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`) confirmed the substrate works end-to-end but exposed two next-layer wins that close round-trip waste:

- **Theme H1 — Fail fast on `output_schema` violation**: when the agent writes its `output_file`, the wheel hooks validate against the declared `output_schema` IN THE SAME TURN. On mismatch, the hook returns a structured diagnostic naming expected vs actual keys; the agent re-writes without leaving the turn. Today the mismatch only surfaces at the NEXT step's input-resolution tick — one full round-trip later.
- **Theme H2 — Surface the contract in Stop-hook feedback**: the Stop-hook feedback for an agent step includes the resolved `## Resolved Inputs` block, the post-`{{VAR}}`-substituted `instruction:`, and the declared `output_schema:` verbatim. The hook already has all three (it just templated them at dispatch). Surfacing them removes the agent's need to read upstream output files or guess key names.

These two themes are tightly coupled UX and ship atomically (NFR-H-6).

## Resolution of PRD Open Questions

The PRD left three Open Questions for the spec phase. Resolved as follows:

- **OQ-H-1 (re-emit contract on agent re-entry?)** — RESOLVED: emit the contract block on **first entry per step only**. After the first emission the agent already has the contract in its turn context (Theme H1 re-write happens within that same turn). Re-emission on every re-entry would bloat feedback for steps that bounce between writing-and-validating multiple times. Encoded in **FR-H2-5**.
- **OQ-H-2 (delete bad output_file on validation failure?)** — RESOLVED: **leave the file in place**. The next write overwrites it idempotently, and the agent (or a debugging human) may want to inspect the rejected file's contents. Deletion would be cleaner state but actively destroys diagnostic information. Encoded in **FR-H1-5**.
- **OQ-H-3 (new error code or reuse existing tripwire reasons?)** — RESOLVED: introduce a **new error reason**: `reason=output-schema-violation`. Distinct from `preprocess-tripwire`, `unresolved-or-invalid`, etc. Easier to grep in archives, and the failure mode is genuinely new (not a hook-internal error — an agent contract violation surfacing through the hook). Encoded in **FR-H1-6**.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Fail fast on output_schema violation (Priority: P1)

A wheel agent step declares `output_schema:` on its workflow JSON. The agent dispatches, writes its `output_file`, and the file is missing a declared key (or has unexpected keys). Today: the workflow advances, the next step's `inputs:` resolver fails, the agent must re-enter the prior step a full Stop tick later, re-read upstream output files, guess at the contract, and try again. Tomorrow: the Stop-hook (or a sibling validator hook) detects the mismatch in the same turn, returns a structured diff naming missing/unexpected keys, and the agent overwrites `output_file` without leaving the turn.

**Why this priority**: P1 because the round-trip waste is the canonical shape of friction this PRD targets. Multiplied across all steps in a real workflow run, it adds material cost and latency. The seed evidence (`.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`) shows one such retry per `/kiln:kiln-report-issue` invocation today.

**Independent Test**: Author a fixture with an agent step declaring `output_schema: {issue_file: "$.issue_file"}` whose dispatched agent writes `{"action": "added", "backlog_path": "..."}` (wrong key). Assert: (a) the bad output is detected in the same turn, (b) the hook emits a structured diagnostic naming `Expected: issue_file`, `Actual: action, backlog_path`, `Missing: issue_file`, `Unexpected: action, backlog_path`, (c) the workflow does NOT advance to the next step, (d) on the corrective re-write, the workflow advances normally. Swap `output_schema` validation off and assert the test fails (mutation tripwire).

**Acceptance Scenarios**:

1. **Given** an agent step whose workflow JSON declares `output_schema: {<keys>}`, **When** the agent writes `output_file` with the wrong key shape, **Then** the validator runs in the SAME turn and the Stop-hook returns `decision=block` with a structured diagnostic naming expected/actual/missing/unexpected keys — without advancing the workflow cursor.
2. **Given** the validation failure body returned to the agent, **When** the agent overwrites `output_file` with the correct keys in the SAME turn, **Then** the next validation pass succeeds and the workflow advances normally.
3. **Given** a passing validation, **When** the Stop-hook composes its feedback body, **Then** the validator emits NO extra body — only the existing "step in progress" or "advance" feedback (silent on success).
4. **Given** the validator itself errors (jq parse error on a malformed `output_file` JSON, missing `output_schema`), **When** the Stop-hook handles the error, **Then** it emits a distinct error body — NOT silently fall through to "looks valid." (NFR-H-7)
5. **Given** an agent step WITHOUT `output_schema:` (legacy workflow shape), **When** the agent writes `output_file`, **Then** no output validation runs and the Stop-hook feedback body is byte-identical to today (NFR-H-3).

---

### User Story 2 — Surface the contract in Stop-hook feedback (Priority: P1)

A wheel agent step declares `inputs:`, `instruction:`, and `output_schema:` on its workflow JSON. The wheel runtime dispatches the step. Today: the agent receives the templated instruction with `## Resolved Inputs` prepended at dispatch (PR #166), but if the agent re-enters via a Stop hook (e.g. after a Theme H1 validation failure + re-write loop, or after a fresh tick), the Stop-hook's feedback is just `"Step '<id>' is in progress. Write your output to: <path>"` — the agent has lost the contract. Tomorrow: the Stop-hook feedback for an agent step that declares any of `{inputs, instruction, output_schema}` includes the same `## Resolved Inputs` block + post-substitution `## Step Instruction` + `## Required Output Schema` block — the contract is durable across re-entries.

**Why this priority**: P1 because Theme H2 is the mechanical pair to Theme H1: if H1 surfaces a mismatch and asks the agent to re-write, the agent needs to see the schema to comply. Without H2, H1's re-write loop devolves to "you wrote the wrong shape — figure out the right shape from elsewhere." With both, the agent has everything it needs in-turn.

**Independent Test**: Author a fixture with an agent step declaring all three (`inputs:` + `instruction:` + `output_schema:`). Trigger a Stop tick on the step (after the agent has been dispatched but before output is written). Assert the Stop-hook feedback body contains `## Resolved Inputs`, `## Step Instruction` (post-substitution), and `## Required Output Schema` sections. Swap H2 surfacing off and assert the byte-identical legacy feedback returns (mutation tripwire). Run the SAME fixture against a step with NEITHER `inputs:` NOR `output_schema:` and assert the feedback body is byte-identical to today (NFR-H-3 strict back-compat).

**Acceptance Scenarios**:

1. **Given** an agent step declaring `inputs:`, **When** the Stop-hook composes feedback for the step's first entry per workflow run, **Then** the body includes a `## Resolved Inputs` block matching the same content the dispatch path prepends to the agent's prompt.
2. **Given** an agent step declaring `instruction:`, **When** the Stop-hook composes feedback, **Then** the body includes the post-`{{VAR}}`-substitution instruction text under a `## Step Instruction` heading.
3. **Given** an agent step declaring `output_schema:`, **When** the Stop-hook composes feedback, **Then** the body includes the schema verbatim under a `## Required Output Schema` heading, formatted as a fenced JSON code block.
4. **Given** an agent step with NEITHER `inputs:` NOR `output_schema:` (legacy shape), **When** the Stop-hook composes feedback, **Then** the body is byte-identical to today (no contract block emitted).
5. **Given** the agent re-enters the SAME step (e.g. after a Theme H1 validation failure + re-write — the cursor stays on this step until its output validates), **When** the Stop-hook composes feedback for the second-or-later tick, **Then** the contract block is suppressed (emit-once-per-step-entry per FR-H2-5 / OQ-H-1) — the agent already has it from the first entry. The "Step in progress. Write your output to: <path>" reminder still appears.

---

### User Story 3 — Round-trip count drops on `/kiln:kiln-report-issue` live smoke (Priority: P1 — HARD GATE)

The PRD's headline metric (SC-H-1, SC-H-2) is round-trip count on a fresh `/kiln:kiln-report-issue` invocation post-PRD compared to the post-PR-#166 baseline. Today: 1 retry observed in the seed live smoke (`.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`). After this PRD: zero output-schema-mismatch retries on a fresh invocation, AND the total round-trip count drops by at least 1 (or stays flat — never regresses).

**Why this priority**: P1 / hard gate because audit fixtures alone are NOT sufficient verification (NFR-H-4). PR #166's retro flagged the audit-gap pattern: implementers can write fixtures that pass without exercising the wheel runtime end-to-end. This PRD encodes the live-smoke gate explicitly.

**Independent Test**: Run `/kiln:kiln-report-issue "<test description>"` against a clean repo (no prior session state). Compare the resulting state archive's `command_log` arrays against the post-PR-#166 baseline — assert zero `reason=output-schema-violation` entries AND total Stop-hook tick count ≤ baseline.

**Acceptance Scenarios**:

1. **Given** a clean repo on this branch with the PRD shipped, **When** `/kiln:kiln-report-issue` runs end-to-end, **Then** the resulting state archive at `.wheel/history/success/` contains zero `reason=output-schema-violation` entries in any step's `command_log`.
2. **Given** the same run, **When** total Stop-hook tick count is computed across all steps in the archive, **Then** the count is at most equal to the post-PR-#166 baseline (the seed run; baseline = 2 turns per the live-smoke issue's pre/post comparison).
3. **Given** the auditor agent in the pipeline, **When** it inspects the live-smoke archive, **Then** it cites the archive path AND a per-step `command_log` summary in its compliance report — fixture-existence-only is a blocker per NFR-H-1.

---

### User Story 4 — Loud failure on validator runtime errors (Priority: P2)

The output-side validator function may itself error for reasons unrelated to the agent's output: `jq` parse error on a malformed `output_file`, missing `output_schema:` declaration when one was expected (logic bug), or filesystem error reading the file. Today (post-PRD): no codepath exists. Tomorrow: validator runtime errors emit a distinct error body — NOT a silent "looks valid" fallthrough.

**Why this priority**: P2 because it's a correctness gate on the validator, separate from the user-facing happy path. Maps directly to NFR-H-7.

**Independent Test**: Author a fixture where the agent writes a malformed `output_file` (e.g. `not valid json`) under a step declaring `output_schema:`. Assert the Stop-hook returns `reason=output-schema-validator-error` (distinct from `output-schema-violation`) with a body naming the underlying error (e.g. `jq: parse error`). Then mutate the validator to swallow the error silently and assert the test fails.

**Acceptance Scenarios**:

1. **Given** an agent step with `output_schema:` declared and an `output_file` that is not valid JSON, **When** the Stop-hook runs the validator, **Then** the hook emits `reason=output-schema-validator-error` (distinct code from FR-H1-6's `output-schema-violation`) and the body names the underlying parse failure.
2. **Given** the validator's exit codes documented in `contracts/interfaces.md`, **When** the Stop-hook composes its response, **Then** it distinguishes (a) validation-passed (silent), (b) validation-violated (FR-H1-6 reason), and (c) validator-errored (FR-H1-7 reason) — three exit shapes, no overlap.

---

## Functional Requirements

### Theme H1 — Fail fast on output_schema violation

- **FR-H1-1** *(from PRD)*: When the wheel hooks detect that an agent step's `output_file` was just written, they MUST run output-schema validation against the declared `output_schema:` BEFORE returning to the agent. Validation hook fires from `post-tool-use.sh` (immediate — runs as soon as the Write tool completes) AND `stop.sh` (defense-in-depth — catches cases where post-tool-use was missed).
- **FR-H1-2** *(from PRD)*: On validation failure, the hook MUST return a structured, multi-line error body in the form:
  ```
  Output schema violation in step '<step-id>'.
    Expected keys (from output_schema): <comma-separated, sorted>
    Actual keys in <output_file_path>: <comma-separated, sorted>
    Missing: <comma-separated, sorted>
    Unexpected: <comma-separated, sorted>
  Re-write the file with the expected keys and try again.
  ```
  Sort order is `LC_ALL=C` lexicographic for reproducibility (NFR-H-3 byte-identity for snapshot tests). When `Missing` or `Unexpected` is empty, that line is OMITTED entirely (not "Missing: " with trailing space).
- **FR-H1-3** *(from PRD)*: The agent MUST be able to re-write `output_file` and trigger another validation pass without leaving the current turn. No extra Stop tick is required between the bad write and the corrected write. Implementation: post-tool-use validation runs synchronously; on violation it returns `decision=block reason=...` to the agent's same turn, and the cursor remains on the current step (status unchanged from `working`).
- **FR-H1-4** *(from PRD)*: When validation passes, the hook MUST emit no extra body — only the existing post-tool-use advance behavior (mark step done, advance cursor) or Stop-hook "step in progress / advance" feedback. The validator is silent on success.
- **FR-H1-5** *(resolves OQ-H-2)*: When validation fails, the hook MUST NOT delete the bad `output_file`. The next agent write overwrites it idempotently. Rationale: preserves rejected-output for inspection.
- **FR-H1-6** *(resolves OQ-H-3)*: Validation-failure responses MUST emit a distinct error reason: `reason=output-schema-violation`. Logged via `wheel_log` and visible in `.wheel/logs/wheel-<sid>.log`. Distinct from `preprocess-tripwire`, `unresolved-or-invalid`, etc.
- **FR-H1-7** *(NFR-H-7 promotion)*: Validator runtime errors (jq parse failure on a malformed `output_file`, fs error, etc.) MUST emit `reason=output-schema-validator-error` — distinct from FR-H1-6. The body names the underlying error class (e.g. `output_file is not valid JSON: <jq error head>`). Silent fallthrough to "validation passed" is a hard tripwire (NFR-H-2).
- **FR-H1-8**: Output validation only runs when the step declares `output_schema:`. Steps without `output_schema:` (legacy shape) skip validation entirely — no codepath, no log line, no perf cost (NFR-H-3 byte-identical back-compat).

### Theme H2 — Surface the contract in Stop-hook feedback

- **FR-H2-1** *(from PRD)*: For an agent step whose workflow JSON declares `inputs:`, the Stop-hook feedback body MUST include the resolved `## Resolved Inputs` block — formatted IDENTICALLY to the block PR #166 prepends to the agent's prompt at dispatch (`context_build` output). Same content; same heading; same per-input bullet shape `- **<VAR>**: <resolved-value>`.
- **FR-H2-2** *(from PRD)*: For an agent step whose workflow JSON declares `instruction:`, the Stop-hook feedback body MUST include the post-`{{VAR}}`-substitution instruction text under a `## Step Instruction` heading. Substitution uses the same resolved map computed at dispatch — NOT recomputed from scratch (cached on state file at dispatch time, read by Stop-hook).
- **FR-H2-3** *(from PRD)*: For an agent step whose workflow JSON declares `output_schema:`, the Stop-hook feedback body MUST include the schema declaration verbatim under a `## Required Output Schema` heading, formatted as a fenced JSON code block (\`\`\`json … \`\`\`). The schema text is the JSON serialization of the `.output_schema` field exactly as declared in the workflow JSON (key order preserved via `jq -c .output_schema`).
- **FR-H2-4** *(from PRD)*: When an agent step has NEITHER `inputs:` NOR `output_schema:` (legacy workflow), the Stop-hook feedback body MUST be byte-identical to today's behavior. NO contract block emitted; "Step '<id>' is in progress. Write your output to: <path>" remains the entire body. NFR-H-3 strict back-compat.
- **FR-H2-5** *(resolves OQ-H-1)*: The Stop-hook MUST emit the surfaced contract block exactly **once per step entry** — re-entering the same step (e.g. after a Theme H1 validation failure + re-write) MUST suppress the contract block to avoid duplication. Implementation: state file gains a per-step boolean field `contract_emitted` (default `false`), set to `true` after first emission; Stop-hook reads the flag before composing the contract block. The "Step in progress" reminder still emits unconditionally.
- **FR-H2-6**: When at least one of `{inputs, instruction, output_schema}` is declared, the Stop-hook feedback body composes the contract block in the deterministic order: `## Resolved Inputs` → `## Step Instruction` → `## Required Output Schema`. Sections that don't apply (e.g. step has `output_schema:` but no `inputs:`) are omitted; the remaining sections retain their order.
- **FR-H2-7**: Contract emission is decoupled from Stop-hook tick advance behavior. If the Stop-hook is composing a "step is in progress" reminder body (output not yet written), the contract block prepends the reminder. If the Stop-hook is advancing past a completed step (output written and validated), no contract block is emitted (the step is done — surfacing its contract is meaningless).

## Non-Functional Requirements

- **NFR-H-1 (testing — explicit)**: Every FR-H1-* and FR-H2-* lands with at least one fixture under `plugin-wheel/tests/`. Implementers MUST invoke `/kiln:kiln-test plugin-wheel <fixture>` for each authored fixture AND `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` (the live-smoke substrate proven in PR #166) before marking their task complete. Verdict report paths cited in friction note. Fixture-file existence WITHOUT an invocation report is a hard auditor blocker.
- **NFR-H-2 (silent-failure tripwires)**: Each documented failure mode has a regression test that fails when the failure becomes silent:
  - Validator runs but emits no diagnostic on a known-bad output → tripwire fixture mutates the validator to silently exit 0 and asserts the violation case fires.
  - Instruction surfacing skipped on a step that declared `inputs:` → tripwire fixture mutates `compose_contract_block` to emit empty and asserts the back-compat snapshot diff comes up non-empty.
  - Back-compat regression on legacy step → byte-snapshot diff against captured pre-PRD output.
- **NFR-H-3 (backward compat — strict)**: Workflows without `inputs:` or `output_schema:` see byte-identical Stop-hook feedback to today. Verified by re-running an unchanged legacy workflow and diffing the feedback body against a pre-PRD snapshot. Same shape rule as PR #166 NFR-G-3.
- **NFR-H-4 (live-smoke gate — NON-NEGOTIABLE)**: Post-merge live `/kiln:kiln-report-issue` smoke MUST be cited in the PR description's verification checklist with the resulting state-archive path. Audit fixtures alone are not sufficient. Same lesson as PR #166 NFR-G-4 / `.kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md`.
- **NFR-H-5 (perf budget)**: Hook-tick adds at most **50ms** combined for validation + contract surfacing per agent step. Measured via `time` in a kiln-test fixture against a step with up to 5 inputs and a 5-key `output_schema`. Baseline = post-PR-#166 hook-tick wall-clock; measured on the same hardware.
- **NFR-H-6 (atomic shipment)**: Theme H1 + Theme H2 land in the SAME commit (or same squash-merged PR per PR-#166's Path-B precedent). They are tightly coupled UX.
- **NFR-H-7 (loud failure on validator runtime errors)**: Validator runtime errors emit `reason=output-schema-validator-error` (FR-H1-7), not silent fallthrough. NFR-H-2 includes a tripwire fixture for this.

## Success Criteria *(measurable; PRD-owned)*

### Headline (HARD GATE — required to ship)

- **SC-H-1**: A fresh `/kiln:kiln-report-issue` post-PRD live smoke shows **zero** output-schema-mismatch retries in the resulting state-archive's `command_log` arrays. Baseline = 1 retry, observed in `.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`.
- **SC-H-2**: The total round-trip count for `/kiln:kiln-report-issue` (Stop-hook ticks across all steps) drops by at least 1 in the same smoke, OR stays flat — never regresses. Baseline = 2 turns total per the seed live smoke.

### Secondary (informational)

- **SC-H-3**: Manually inject a wrong-key output write in a kiln-test fixture; verify the Stop-hook returns a structured FR-H1-2 diagnostic naming the diff in the same turn.
- **SC-H-4**: Manually neutralize the FR-H2-1/H2-2/H2-3 surfacing logic in a kiln-test fixture; verify the back-compat snapshot diff comes up non-empty (NFR-H-2 mutation tripwire).
- **SC-H-5**: Hook-tick perf measurement: validation + surfacing combined adds ≤50ms per agent step on a step with 5 inputs + 5-key `output_schema` (NFR-H-5).

### Process

- **SC-H-6**: NFR-H-4 satisfied — the live `/kiln:kiln-report-issue` smoke is cited in the PR description's verification checklist with the state-archive path, run before merge.

## Edge Cases

- **`output_file` is a JSON envelope vs flat object**: PR #166's `extract_field` parses upstream output as JSON and walks `$.foo.bar` paths. The output validator MUST use the same parser — any JSON shape that PR #166 can extract from is also a shape this validator must accept. Flat top-level objects are the v1 expectation; nested paths in `output_schema:` (e.g. `{result: {ok: "$.result.ok"}}`) are out-of-scope for v1 validation (the existing PR #166 directive grammar already supports them; v1 just enforces top-level key presence).
- **Empty `output_schema: {}`**: treated as "no schema declared" — validation is a no-op (back-compat with workflows that ship the field as a stub).
- **`output_schema` references unwritten upstream**: caught at workflow_load by `workflow_validate_inputs_outputs` (PR #166 rule 5). Out-of-scope for runtime validator.
- **Concurrent writes to `output_file`**: agent writes are serialized at the tool layer; no race-condition handling needed at the validator level.
- **Validator caches resolved-inputs map for FR-H2-1 surfacing**: dispatch-time `resolve_inputs` output (the `_resolved_map` JSON) is persisted onto the state file at the per-step record (`.steps[idx].resolved_inputs`) for Stop-hook re-read. NOT recomputed on every Stop tick (NFR-H-5 perf budget).
- **Agent never writes the output file**: existing "Step in progress. Write your output to: …" reminder behavior is preserved. Contract block prepends the reminder on first entry per FR-H2-7.

## Out of Scope (v1)

- Validating nested `output_schema:` paths (top-level keys only in v1).
- A `--terse` mode that omits the instruction text (R-H-1 mitigation deferred — measure first).
- Migrating existing agent steps to use `output_schema:` (separate audit-and-migrate PRD per PRD §Non-Goals).
- Changing the Stop-hook wire shape (still `decision/reason/additionalContext`).
- New step types (PRD §Non-Goals).

## Dependencies

- PR #166 substrate: `plugin-wheel/lib/workflow.sh::workflow_validate_inputs_outputs`, `plugin-wheel/lib/resolve_inputs.sh::resolve_inputs`, `plugin-wheel/lib/context.sh::context_build`, `plugin-wheel/lib/dispatch.sh::dispatch_agent` (post_tool_use branch), `plugin-wheel/hooks/stop.sh`.
- `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` substrate (live-smoke driver).

No new runtime dependencies (Bash 5.x + jq + python3 only — same as PR #166).

## Resolved Clarifications

All three PRD Open Questions resolved at top of spec (OQ-H-1 → FR-H2-5; OQ-H-2 → FR-H1-5; OQ-H-3 → FR-H1-6/FR-H1-7).
