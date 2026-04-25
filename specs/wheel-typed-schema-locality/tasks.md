# Tasks: Wheel Typed-Schema Locality

**Branch**: `build/wheel-typed-schema-locality-20260425`
**Spec**: `specs/wheel-typed-schema-locality/spec.md`
**Plan**: `specs/wheel-typed-schema-locality/plan.md`
**Contracts**: `specs/wheel-typed-schema-locality/contracts/interfaces.md`

Atomic shipment per NFR-H-6 — Phase 1–4 are ONE squash-merge PR. Phase 5 (docs) is in the same PR.

Implementer MUST mark each task `[X]` IMMEDIATELY after completing it (Article VIII). Hooks block raw `plugin-wheel/` edits until at least one `[X]` exists.

Implementer MUST invoke `/kiln:kiln-test plugin-wheel <fixture>` for every authored fixture AND `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` before marking T020 complete (NFR-H-1). Verdict report paths cited in `agent-notes/implementer.md`.

---

## Phase 1 — Foundation: state-file extensions + validator scaffold

- [X] **T001** [P] Add `state_set_resolved_inputs <state_file> <step_index> <resolved_map_json>` to `plugin-wheel/lib/state.sh` per `contracts/interfaces.md` §4.1. Mirror existing `state_set_step_status` pattern (jq + temp file + atomic mv). FR reference: FR-H2-1 (caching plumbing).
- [X] **T002** [P] Add `state_set_contract_emitted <state_file> <step_index> <bool>` to `plugin-wheel/lib/state.sh` per §4.2. Validates `$3` ∈ {true,false} or exits 1. FR: FR-H2-5.
- [X] **T003** [P] Add `state_get_contract_emitted <state_file> <step_index>` to `plugin-wheel/lib/state.sh` per §4.3. Returns `false` for missing field via `// false`. FR: FR-H2-5.
- [X] **T004** Add `workflow_validate_output_against_schema <step_json> <output_file_path>` to `plugin-wheel/lib/workflow.sh` per §1. v1 validates top-level key presence only. Three exit codes (0/1/2) per contract. FRs: FR-H1-1, FR-H1-2, FR-H1-6, FR-H1-7, FR-H1-8.

## Phase 2 — Theme H1: validate output on write

- [X] **T010** Wire validator into `dispatch.sh::dispatch_agent` `post_tool_use` branch per §2.1. Insertion at line ~833 BEFORE `state_set_step_status … done`. Three branches: pass (silent), violation (block + reason), runtime-error (block + reason). FRs: FR-H1-1, FR-H1-3, FR-H1-5, FR-H1-6, FR-H1-7.
- [X] **T011** Wire validator into `dispatch.sh::dispatch_agent` `stop` branch per §2.2. Defense-in-depth — same shape as T010. Insertion at line ~624. FR: FR-H1-1.
- [X] **T012** Wire validator into `dispatch.sh::dispatch_agent` `teammate_idle` branch per §2.3. Mirror of T011. FR: FR-H1-1.

## Phase 3 — Theme H2: contract surfacing

- [X] **T013** Add `context_compose_contract_block <step_json> <resolved_map_json>` to `plugin-wheel/lib/context.sh` per §3. Pure formatting. Reuses `substitute_inputs_into_instruction` from preprocess.sh. Section omission rules per FR-H2-6. FRs: FR-H2-1, FR-H2-2, FR-H2-3, FR-H2-6, FR-H2-4 (back-compat empty-string return).
- [X] **T014** Persist `_resolved_map` to state via `state_set_resolved_inputs` in `dispatch_agent` `stop` branch (line ~603) per §6. FR: FR-H2-1.
- [X] **T015** Mirror T014 persistence in `dispatch_agent` `teammate_idle` branch (line ~693). FR: FR-H2-1.
- [X] **T016** Wire contract-block emission into `dispatch_agent` `stop` branch's "Output file expected but not yet produced — short reminder" else-leaf (line ~679) per §5. Read `contract_emitted` flag, compose block on first entry, set flag, prepend block to reminder body. FRs: FR-H2-5, FR-H2-7, FR-H2-4 byte-compat path.
- [X] **T017** Mirror T016 in `dispatch_agent` `teammate_idle` branch (line ~759). FR: FR-H2-5.

## Phase 4 — Test fixtures (the discipline gate per NFR-H-1)

- [ ] **T020** [P] Author `plugin-wheel/tests/output-schema-validation-violation/run.sh` per plan.md Phase 4. Asserts FR-H1-2 diagnostic shape (Expected/Actual/Missing/Unexpected sections, LC_ALL=C sort), FR-H1-6 reason in log, cursor un-advanced, FR-H1-5 (bad output_file remains on disk). Includes mutation tripwire that swaps the validator to silent-exit-0 and asserts the test fails (NFR-H-2).
- [ ] **T021** [P] Author `plugin-wheel/tests/output-schema-validation-pass/run.sh`. Correctly-shaped output → validator silent + advance happens. FRs: FR-H1-4, FR-H1-8.
- [ ] **T022** [P] Author `plugin-wheel/tests/output-schema-validator-runtime-error/run.sh`. Malformed JSON in output_file → FR-H1-7 reason + distinct body. Mutation tripwire: swap exit-2 to exit-0 silent. FRs: FR-H1-7, NFR-H-7.
- [ ] **T023** [P] Author `plugin-wheel/tests/contract-block-emit-once/run.sh`. Two consecutive Stop ticks on a `working` step with `inputs:`+`instruction:`+`output_schema:` declared. Tick 1 → contract block in body. Tick 2 → contract block ABSENT. Mutation tripwire: swap `contract_emitted` to never-set and assert tick 2 re-emits. FR: FR-H2-5.
- [ ] **T024** [P] Author `plugin-wheel/tests/contract-block-back-compat/run.sh`. Step with NEITHER `inputs:` NOR `output_schema:`. Snapshot byte-diff against captured pre-PRD body. Mutation tripwire: swap back-compat branch to emit contract block and assert snapshot diff fails. FRs: FR-H2-4, NFR-H-3.
- [ ] **T025** [P] Author `plugin-wheel/tests/contract-block-shape/run.sh`. Step with all three declared. Asserts body contains `## Resolved Inputs` → `## Step Instruction` → `## Required Output Schema` in order; output_schema rendered as fenced JSON code block; FR-H2-7 (no contract on advance-past-done tick). FRs: FR-H2-1, FR-H2-2, FR-H2-3, FR-H2-6, FR-H2-7.
- [ ] **T026** [P] Author `plugin-wheel/tests/contract-block-partial/run.sh`. Step with ONLY `output_schema:` declared. Asserts only `## Required Output Schema` emits; `## Resolved Inputs` and `## Step Instruction` ABSENT. FR: FR-H2-6 omission rule.
- [ ] **T027** Extend `plugin-wheel/tests/hydration-perf/run.sh` (existing) to assert validator + contract surfacing combined ≤50ms on a step with 5 inputs + 5-key output_schema. NFR: NFR-H-5.
- [ ] **T028** Invoke `/kiln:kiln-test plugin-wheel <fixture>` for every fixture authored in T020–T027. Cite each verdict report path (`.kiln/logs/kiln-test-<uuid>.md`) in `specs/wheel-typed-schema-locality/agent-notes/implementer.md`. Authoring without invoking is a hard auditor blocker (NFR-H-1).
- [ ] **T029** Invoke `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` (the live-smoke substrate). Cite verdict path in implementer notes. NFR: NFR-H-1.
- [ ] **T030** Run canonical `/kiln:kiln-report-issue "<test description>"` end-to-end against a clean repo. Assert: zero `output-schema-violation` entries in resulting state archive's `command_log` arrays (SC-H-1); total Stop-hook tick count ≤ baseline (SC-H-2). Cite `.wheel/history/success/<archive>.json` path in PR description verification checklist (NFR-H-4, SC-H-6).

## Phase 5 — Documentation (in same PR per NFR-H-6)

- [ ] **T040** Add "Typed-schema locality" section to `plugin-wheel/README.md` documenting Theme H1 + H2 with a worked example showing a violation + diagnostic output and a happy-path contract block.
- [ ] **T041** Update `CLAUDE.md` "Recent Changes" block via the `/kiln:kiln-build-prd` retrospective phase. Manual edit not required at implementer time — retrospective handles it.

## Verification gates (auditor-checked, per NFR-H-1 / NFR-H-4)

- [ ] **G1** Every FR-H1-* and FR-H2-* mapped to a fixture per plan.md §Coverage matrix.
- [ ] **G2** Every fixture has a cited `.kiln/logs/kiln-test-<uuid>.md` PASS verdict in `agent-notes/implementer.md`. Fixture-existence-only is a blocker.
- [ ] **G3** `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` invoked + verdict path cited.
- [ ] **G4** Live `/kiln:kiln-report-issue` smoke run end-to-end + state-archive path cited in PR description.
- [ ] **G5** SC-H-1 satisfied — zero `output-schema-violation` entries in the live-smoke archive.
- [ ] **G6** SC-H-2 satisfied — total Stop-hook tick count ≤ post-PR-#166 baseline.
- [ ] **G7** NFR-H-3 byte-identity verified on `contract-block-back-compat/` fixture.
- [ ] **G8** NFR-H-5 perf budget verified on `hydration-perf/` extended fixture.
- [ ] **G9** Atomic shipment verified — Theme H1 + H2 in same squash-merge commit (NFR-H-6).
- [ ] **G10** Friction note `agent-notes/implementer.md` exists and cites verdict paths (FR-009 of process-governance).

## Parallelism notes

- T001/T002/T003 ([P]) — independent state.sh additions, no interdependency.
- T020/T021/T022/T023/T024/T025/T026 ([P]) — independent fixtures under separate dirs.
- T010/T011/T012 are sequential (same file `dispatch.sh`, ordered insertion-line dependencies).
- T013 is independent of T010-T012 (different file `context.sh`) and CAN proceed in parallel with them.
- T014/T015 depend on T001 (state_set_resolved_inputs).
- T016/T017 depend on T002, T003, T013, T014, T015.
- T028/T029/T030 are gates run after T010–T027 complete.
