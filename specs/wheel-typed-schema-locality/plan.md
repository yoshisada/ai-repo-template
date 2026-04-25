# Implementation Plan: Wheel Typed-Schema Locality

**Branch**: `build/wheel-typed-schema-locality-20260425`
**Spec**: `specs/wheel-typed-schema-locality/spec.md`
**Approach**: Bash 5.x + `jq` + `python3` extensions to existing PR #166 substrate. No new runtime deps.

## Summary

Two tightly-coupled extensions to the wheel runtime:
1. **Output-side validator** (Theme H1) — new function in `plugin-wheel/lib/workflow.sh` (or `resolve_inputs.sh`) wrapping the existing JSON extraction logic. Called from `post-tool-use.sh` (immediate fail-fast on Write) and `stop.sh` (defense-in-depth). Distinct error reasons `output-schema-violation` (FR-H1-6) and `output-schema-validator-error` (FR-H1-7).
2. **Contract-block composer** (Theme H2) — new function in `plugin-wheel/lib/context.sh` that emits `## Resolved Inputs` + `## Step Instruction` + `## Required Output Schema` markdown for an agent step. Called from `dispatch_agent`'s `stop` branch when the step is `working` and the agent has not yet written `output_file`. Cached resolved-inputs map persisted on state file (`.steps[idx].resolved_inputs`) at dispatch time for Stop-hook re-read; emit-once gated by per-step boolean `.steps[idx].contract_emitted` (FR-H2-5).

## Phases

### Phase 1 — Validator wrapper + state-file extensions (foundation)

Lays the substrate for both themes. Output-side validator function lives next to PR #166's `workflow_validate_inputs_outputs` for grep-locality; state-file fields (`resolved_inputs`, `contract_emitted`) added via `state_set_*` helpers.

**Files touched**:
- `plugin-wheel/lib/workflow.sh` — add `workflow_validate_output_against_schema()` (output-side wrapper around PR #166's extract logic). Lives next to existing input-side validator.
- `plugin-wheel/lib/state.sh` — add `state_set_resolved_inputs()`, `state_set_contract_emitted()`, `state_get_contract_emitted()` helpers. Pure structural extension; no behavior change to existing fields.
- `plugin-wheel/lib/dispatch.sh::dispatch_agent` — `stop` branch's `pending → working` transition writes `_resolved_map` to state file via `state_set_resolved_inputs` (fires unconditionally; absent → empty `{}` so legacy steps see no diff).

### Phase 2 — Theme H1: validate output on write + Stop-hook fail-fast

Wires the validator into both hooks. Post-tool-use is the primary fail-fast path; Stop-hook is defense-in-depth.

**Files touched**:
- `plugin-wheel/lib/dispatch.sh::dispatch_agent` — `post_tool_use` branch's "Agent wrote to output file" detection (line ~833): BEFORE `state_set_step_status … done`, run `workflow_validate_output_against_schema`. On violation: emit `decision=block reason=output-schema-violation` body per FR-H1-2; cursor stays on this step (status remains `working`, NOT `done`); contract_emitted unchanged. On validator runtime error: emit `decision=block reason=output-schema-validator-error` body. On pass: silent — fall through to existing advance logic.
- `plugin-wheel/lib/dispatch.sh::dispatch_agent` — `stop` branch's `working → done` transition (line ~621): same validator call as defense-in-depth. Identical violation/error paths.
- `plugin-wheel/hooks/post-tool-use.sh` — no changes needed; the validation logic lives in dispatch.sh per the existing layering (post_tool_use hook already calls dispatch_step → dispatch_agent → post_tool_use branch).
- `plugin-wheel/lib/log.sh` (no changes) — `wheel_log` already supports arbitrary `reason=` values.

### Phase 3 — Theme H2: contract-block composer + Stop-hook surfacing

Emits the contract block on Stop-hook ticks while the step is `working` and output not yet written. Reads cached resolved-inputs from state.

**Files touched**:
- `plugin-wheel/lib/context.sh` — new function `context_compose_contract_block(step_json, resolved_map_json)` returning the contract markdown OR empty string when neither `inputs:` nor `output_schema:` declared. Pure formatting; no I/O.
- `plugin-wheel/lib/dispatch.sh::dispatch_agent` — `stop` branch's `working` else-leaf (line ~679, the "Output file expected but not yet produced — short reminder"): BEFORE emitting the reminder, check `state_get_contract_emitted`. If false AND any of `{inputs, instruction, output_schema}` declared, prepend `context_compose_contract_block` output to the reminder body and set `contract_emitted=true`.
- `plugin-wheel/lib/dispatch.sh::dispatch_agent` — `teammate_idle` branch (line ~759): mirror the Stop branch behavior identically (teammates use teammate_idle as their "Stop tick").

### Phase 4 — Test fixtures + tripwires (the discipline gate)

NFR-H-1 says fixtures alone aren't sufficient — invocations are. Each fixture is authored AND invoked via `/kiln:kiln-test plugin-wheel <fixture>`; verdict report path cited in friction note.

**Fixtures authored** (new directories under `plugin-wheel/tests/`):
- `output-schema-validation-violation/` — agent step with `output_schema: {issue_file: "$.issue_file"}`, dispatched agent writes `{"action": "added", "backlog_path": "..."}`. Asserts FR-H1-2 diagnostic shape, FR-H1-6 reason code, cursor un-advanced. Mutates the validator to silently exit 0 and asserts the test fails (NFR-H-2 tripwire).
- `output-schema-validation-pass/` — agent step writes correctly-shaped output. Asserts validator silent, advance happens normally (FR-H1-4).
- `output-schema-validator-runtime-error/` — agent writes malformed JSON to `output_file`. Asserts FR-H1-7 reason and distinct body (NFR-H-7 tripwire).
- `contract-block-emit-once/` — agent step with `inputs: + instruction: + output_schema:` declared. First Stop tick → contract block in body. Second Stop tick (after agent re-write) → contract block ABSENT (FR-H2-5). Mutates `contract_emitted` to never-set and asserts the second tick re-emits (failure tripwire).
- `contract-block-back-compat/` — agent step with NEITHER `inputs:` NOR `output_schema:`. Asserts feedback body byte-identical to a captured pre-PRD snapshot (NFR-H-3 / FR-H2-4). Mutates the back-compat branch to emit the contract block and asserts the snapshot diff fails.
- `contract-block-shape/` — agent step with all three declared. Asserts the body contains all three sections in order `## Resolved Inputs` → `## Step Instruction` → `## Required Output Schema` (FR-H2-6) AND the schema is a fenced JSON code block (FR-H2-3).
- `contract-block-partial/` — agent step with ONLY `output_schema:` (no `inputs:`/no `instruction:`). Asserts only `## Required Output Schema` emits; other sections absent (FR-H2-6 omission rule).

**Performance fixture extension**:
- `plugin-wheel/tests/hydration-perf/` (existing) — extend assertion to cover validator + contract surfacing combined ≤50ms (NFR-H-5).

**Live-smoke driver invocation** (NFR-H-1, NFR-H-4, SC-H-1, SC-H-2):
- `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` invoked by implementer; verdict report path cited in friction note. Implementer ALSO runs the canonical `/kiln:kiln-report-issue "<test>"` end-to-end and cites the resulting `.wheel/history/success/<archive>.json` path.

### Phase 5 — Documentation

- `plugin-wheel/README.md` — add a "Typed-schema locality" section documenting Theme H1 + H2 behavior with a worked example.
- `plugin-wheel/agents/` (none — wheel is dispatch infrastructure; no agents owned here per the FR-A1 reversal note in CLAUDE.md).
- No CLAUDE.md changes needed (Recent Changes block updated by `/kiln:kiln-build-prd` retrospective phase).

## Test Strategy

Per NFR-H-1: every FR has at least one fixture under `plugin-wheel/tests/`. Per NFR-H-2: every documented failure mode has a mutation tripwire that fails when the failure becomes silent. Per NFR-H-4: live `/kiln:kiln-report-issue` smoke MUST be cited in PR description.

**Coverage matrix (FR → fixture)**:

| FR / NFR | Fixture |
|---|---|
| FR-H1-1, FR-H1-2, FR-H1-3, FR-H1-6 | `output-schema-validation-violation/` |
| FR-H1-4, FR-H1-8 | `output-schema-validation-pass/` |
| FR-H1-5 | covered in `output-schema-validation-violation/` (assertion: bad output_file remains on disk after violation) |
| FR-H1-7 / NFR-H-7 | `output-schema-validator-runtime-error/` |
| FR-H2-1, FR-H2-2, FR-H2-3, FR-H2-6 | `contract-block-shape/` |
| FR-H2-4 / NFR-H-3 | `contract-block-back-compat/` |
| FR-H2-5 (OQ-H-1) | `contract-block-emit-once/` |
| FR-H2-6 omission rule | `contract-block-partial/` |
| FR-H2-7 | covered in `contract-block-shape/` (assertion: no contract on advance-past-done tick) |
| NFR-H-2 (silent-failure tripwires) | mutation cases inside each violation/back-compat fixture |
| NFR-H-5 (perf) | `hydration-perf/` extension |
| NFR-H-1, NFR-H-4, SC-H-1, SC-H-2, SC-H-6 | `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` invocation + canonical live-smoke run |

## Risks & Mitigations

- **R-H-1 (feedback length)** — mitigated by emit-once-per-step (FR-H2-5). If still too long for a 5-input + 5-key fixture, add a `--terse` mode in v2 — out of scope for v1 per spec.
- **R-H-2 (validator runtime errors)** — FR-H1-7 / NFR-H-7 / fixture `output-schema-validator-runtime-error/` close this.
- **R-H-3 (re-entry duplication)** — FR-H2-5 + state field `contract_emitted` close this.
- **R-H-4 (audit-gap recurrence)** — NFR-H-1 mandates kiln-test invocation reports cited in friction notes; auditor blocks on missing citations. NFR-H-4 mandates live-smoke citation in PR description.

## Rollback

The work touches additive extensions to existing functions. Rollback is `git revert <commit-sha>` of the squash-merge PR. State-file fields `resolved_inputs` and `contract_emitted` are read with `// {}` and `// false` defaults — pre-PRD state files remain readable.
