---
description: "Task list for manifest-improvement-subroutine feature implementation"
---

# Tasks: Manifest Improvement Subroutine

**Input**: Design documents from `/specs/manifest-improvement-subroutine/`
**Prerequisites**: spec.md, plan.md, contracts/interfaces.md, data-model.md, research.md, quickstart.md (all present)

**Tests**: Unit + integration tests REQUIRED — constitution II mandates >=80% coverage on new bash scripts, and the silent-on-skip + verbatim-match contracts are untrustworthy without tests.

**Organization**: Tasks grouped by the six user stories from spec.md. US1 (silent-skip), US2 (write proposal), US3 (scope clamp) are all P1 and together form the MVP. US4–US6 add caller wiring, portability, and MCP degradation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Maps task to user story from spec.md (US1..US6)

## Path Conventions

- Plugin source paths (scripts, workflows, skills): rooted at repo root under `plugin-shelf/` and `plugin-kiln/`.
- Test paths: rooted at `tests/unit/` and `tests/integration/` at repo root. (Note: this plugin-source repo does not ship a test suite in `src/` — tests exercise bash scripts directly via `bats` and smoke scripts.)
- Spec artifacts: `specs/manifest-improvement-subroutine/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directories and set up the test harness before any code is written.

- [ ] T001 Create directory `plugin-shelf/scripts/` (may already exist) and `plugin-shelf/skills/propose-manifest-improvement/` at repo root.
- [ ] T002 Create directories `tests/unit/` and `tests/integration/` at repo root for the bash test harness (if absent).
- [ ] T003 [P] Verify `bats-core` is available on the developer machine (used by unit tests). Document install command in `tests/README.md` if the file does not yet exist.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Write the contracts/interfaces.md-mandated bash helpers. All three P1 stories (US1, US2, US3) depend on these helpers behaving correctly.

**CRITICAL**: No user-story phase can begin until Phase 2 is complete — the workflow's silent-skip and verbatim-match guarantees ride on these scripts.

- [ ] T004 [P] [FR-003 FR-004 FR-005 FR-006] Implement `plugin-shelf/scripts/validate-reflect-output.sh` per `contracts/interfaces.md` §validate-reflect-output.sh. Must exit 0 on every outcome (skip or write) and emit exactly one JSON line to stdout. Add FR comment at the top of the script referencing FR-003..FR-006.
- [ ] T005 [P] [FR-010] Implement `plugin-shelf/scripts/derive-proposal-slug.sh` per `contracts/interfaces.md` §derive-proposal-slug.sh. Pure bash pipeline, `LC_ALL=C`, deterministic. Add FR comment referencing FR-010.
- [ ] T006 [P] [FR-005] Implement `plugin-shelf/scripts/check-manifest-target-exists.sh` per `contracts/interfaces.md` §check-manifest-target-exists.sh. Resolves `@manifest/...` via `$VAULT_ROOT` or `.shelf-config`; uses `grep -F -f` for verbatim match (handles multi-line needles). Add FR comment referencing FR-005.
- [ ] T007 [FR-007 FR-008 FR-010 FR-018 FR-019 FR-020] Implement `plugin-shelf/scripts/write-proposal-dispatch.sh` per `contracts/interfaces.md` §write-proposal-dispatch.sh. Orchestrates T004 + T005 + T006. Emits ONE JSON line to stdout; silent on skip; atomic temp-file cleanup via `trap EXIT`. Depends on T004, T005, T006.
- [ ] T008 [P] [FR-003..FR-006] Write unit tests `tests/unit/validate-reflect-output.bats` covering all 6 skip reasons + write path + edge cases (empty JSON, malformed JSON, missing file, boolean `skip`). >=80% line coverage target.
- [ ] T009 [P] [FR-010] Write unit tests `tests/unit/derive-proposal-slug.bats` covering deterministic output, stop-word removal, truncation at word boundary, unicode input, stop-words-only input (exit 1), multi-line input.
- [ ] T010 [P] [FR-005] Write unit tests `tests/unit/check-manifest-target-exists.bats` covering match, non-match, missing file, missing VAULT_ROOT, multi-line verbatim match.
- [ ] T011 [FR-007 FR-018] Write unit test `tests/unit/write-proposal-dispatch.bats` covering: malformed reflect input → skip envelope; skip: true → skip envelope; valid write path → write envelope with correctly derived slug + date; target-not-found → skip envelope.

**Checkpoint**: Foundation ready — all helpers pass unit tests. User-story work can begin.

---

## Phase 3: User Story 1 — Silent no-op on no-propose runs (Priority: P1) MVP

**Goal**: The sub-workflow exists and, when `reflect` emits `{"skip": true}`, the user sees zero output and no proposal file is created.

**Independent Test**: Seed `.wheel/outputs/propose-manifest-improvement.json = {"skip": true}`; invoke `/wheel-run shelf:propose-manifest-improvement`; assert zero files in `@inbox/open/`, empty `write-proposal-mcp.txt`, dispatch envelope == `{"action":"skip"}`, exit 0.

### Implementation for User Story 1

- [ ] T012 [US1] [FR-001 FR-002] Create `plugin-shelf/workflows/propose-manifest-improvement.json` with the 3-step shape defined in `contracts/interfaces.md` §Workflow shape. All command steps reference `${WORKFLOW_PLUGIN_DIR}`. Mark `write-proposal-mcp` as `terminal: true`.
- [ ] T013 [US1] [FR-007 FR-018 FR-020] In the `write-proposal-mcp` agent step's instruction, handle `action: "skip"` by producing NO output and calling no MCP tool. Write the instruction per `contracts/interfaces.md` §write-proposal-mcp. The step's output file MUST remain empty on skip.
- [ ] T014 [US1] [FR-003] In the `reflect` agent step's instruction, include the gate-aware directives from `contracts/interfaces.md` §Agent instruction contract for reflect — explicitly default to `{"skip": true}` when in doubt.

### Tests for User Story 1

- [ ] T015 [US1] [FR-007 FR-020] Write integration test `tests/integration/silent-skip.sh` that seeds a skip reflect output, invokes the workflow, and asserts: exit 0; `@inbox/open/` unchanged; `write-proposal-mcp.txt` empty; dispatch envelope == `{"action":"skip"}`; no stderr emitted by the dispatch command step.

**Checkpoint**: User Story 1 complete — silent-skip invariant holds end-to-end.

---

## Phase 4: User Story 2 — Exact-patch proposal lands in `@inbox/open/` (Priority: P1) MVP

**Goal**: When `reflect` emits a valid propose-shape output that passes the gate, exactly one file appears in `@inbox/open/<date>-manifest-improvement-<slug>.md` with correct frontmatter and four H2 sections, written via MCP.

**Independent Test**: Seed a valid propose reflect output against a real manifest file and verbatim-present `current` text; invoke workflow; assert the single proposal file exists with required frontmatter keys, the four H2 sections in the mandated order, and the `why` is captured verbatim.

### Implementation for User Story 2

- [ ] T016 [US2] [FR-008 FR-009 FR-015 FR-019] In the `write-proposal-mcp` agent step, implement the MCP write per `contracts/interfaces.md` §write-proposal-mcp: compose markdown with exact frontmatter + four H2 sections, call `mcp__claude_ai_obsidian-manifest__create_file`, handle "file already exists" with `-2..-9` suffix retry, exit 0 on success emitting nothing. (This is the same step as T013 — add the write-path branch to the same instruction.)
- [ ] T017 [US2] [FR-009] In the agent instruction, enforce the exact four-H2-sections layout (`## Target`, `## Current`, `## Proposed`, `## Why` in this exact order). No additional sections above or between them. Optional `# Manifest Improvement Proposal` H1 is permitted before the first H2.

### Tests for User Story 2

- [ ] T018 [US2] [FR-008 FR-009 FR-010] Write integration test `tests/integration/write-proposal.sh` that: seeds a propose reflect output where `current` is the first line of a real file under `@manifest/types/`; invokes the workflow; asserts a single `.md` file appears in `@inbox/open/` with filename pattern `<YYYY-MM-DD>-manifest-improvement-<slug>.md`; validates frontmatter keys (`type: proposal`, `target`, `date`); validates the four H2 section headings appear in order.
- [ ] T019 [US2] [FR-005] Write integration test `tests/integration/hallucinated-current.sh`: seeds a propose output where `current` does NOT appear in the target file; asserts force-skip (no file written).
- [ ] T020 [US2] [FR-006] Write integration test `tests/integration/ungrounded-why.sh`: seeds a propose output where `why` is a generic opinion with no run-evidence token; asserts force-skip.

**Checkpoint**: US1 + US2 together deliver the MVP. The sub-workflow silences on empty runs and produces well-formed proposals on actionable runs.

---

## Phase 5: User Story 3 — Target scope is clamped to manifest vault (Priority: P1) MVP

**Goal**: Any reflect output targeting a path outside `@manifest/types/*.md` or `@manifest/templates/*.md` is force-skipped. No proposal ever lands for a non-manifest target.

**Independent Test**: Seed a propose reflect output with a target of `plugin-shelf/skills/shelf-update/SKILL.md`; assert zero files in `@inbox/open/`. Repeat for `@manifest/systems/projects.md` (valid-looking but out of scope since not under `types/` or `templates/`). Repeat for a valid `@manifest/types/mistake.md` → proposal IS written.

### Implementation for User Story 3

- [ ] T021 [US3] [FR-004] The gate in `validate-reflect-output.sh` (T004) enforces the regex `^@manifest/(types|templates)/[A-Za-z0-9_.-]+\.md$`. Add this regex check to `validate-reflect-output.sh` if not already present from T004 and ensure test coverage of the reason code `out-of-scope`.

### Tests for User Story 3

- [ ] T022 [US3] [FR-004] Write integration test `tests/integration/out-of-scope.sh`: covers three targets — (a) a shelf skill file (outside vault), (b) `@manifest/systems/projects.md` (in vault, wrong subdir), (c) `@manifest/types/mistake.md` (valid). Assert: (a) force-skip, (b) force-skip, (c) proposal written.

**Checkpoint**: US1 + US2 + US3 = the MVP. The sub-workflow is runnable standalone, silent on skip, produces well-formed proposals on the happy path, and bounds its scope.

---

## Phase 6: User Story 4 — Wired into three callers (Priority: P2)

**Goal**: Each of `shelf-full-sync`, `report-issue-and-sync`, and `report-mistake-and-sync` includes exactly one sub-workflow step invoking `shelf:propose-manifest-improvement` in the pre-terminal position.

**Independent Test**: Inspect each caller JSON; assert exactly one `type: "workflow"` step with `workflow: "shelf:propose-manifest-improvement"`, positioned immediately before the terminal step. Run each caller end-to-end with a seeded improvement and verify the proposal lands in the same sync pass (kiln callers) or the next sync pass (shelf-full-sync — documented asymmetry per research.md R-007).

### Implementation for User Story 4

- [ ] T023 [P] [US4] [FR-013 FR-014] Edit `plugin-kiln/workflows/report-mistake-and-sync.json`: insert the 3-key sub-workflow step from `contracts/interfaces.md` §Caller integration shape immediately BEFORE the `full-sync` step. Bump workflow `version` minor.
- [ ] T024 [P] [US4] [FR-012 FR-014] Edit `plugin-kiln/workflows/report-issue-and-sync.json`: insert the same step immediately BEFORE the `full-sync` step. Bump `version` minor.
- [ ] T025 [P] [US4] [FR-011 FR-014] Edit `plugin-shelf/workflows/shelf-full-sync.json`: insert the same step immediately BEFORE the terminal `self-improve` step. Bump `version` minor.
- [ ] T026 [US4] [FR-017] Create `plugin-shelf/skills/propose-manifest-improvement/SKILL.md` — thin skill wrapper that runs `/wheel-run shelf:propose-manifest-improvement`. Follow the SKILL.md conventions used by existing shelf skills (frontmatter with `name`, `description`, plus a short body).

### Tests for User Story 4

- [ ] T027 [US4] [FR-011 FR-012 FR-013 FR-014] Write integration test `tests/integration/caller-wiring.sh` that parses each of the three caller JSON files with `jq` and asserts: (a) exactly one step with `workflow == "shelf:propose-manifest-improvement"`; (b) that step's index == (steps.length − 2), i.e., immediately before the terminal step; (c) terminal step is still present and `terminal == true`.

**Checkpoint**: All three callers delegate to the sub-workflow uniformly. The sub-workflow is reachable via `/shelf:propose-manifest-improvement` standalone.

---

## Phase 7: User Story 5 — Plugin portability (Priority: P2)

**Goal**: Every command step resolves its script via `${WORKFLOW_PLUGIN_DIR}`. No repo-relative `plugin-shelf/scripts/...` paths.

**Independent Test**: Grep the workflow JSON for `plugin-shelf/scripts/` — must return zero matches. Optionally install the plugin into a second consumer repo and run the workflow end-to-end from there.

### Implementation for User Story 5

- [ ] T028 [US5] [FR-016] Audit `plugin-shelf/workflows/propose-manifest-improvement.json`: `jq -r '.steps[] | select(.type=="command") | .command' | grep -F 'plugin-shelf/scripts/'` must return empty. If any match, rewrite those steps to use `${WORKFLOW_PLUGIN_DIR}`.

### Tests for User Story 5

- [ ] T029 [US5] [FR-016] Write integration test `tests/integration/portability.sh`: runs the grep above and asserts no matches. Also asserts every command step in the new workflow contains the substring `${WORKFLOW_PLUGIN_DIR}`.

**Checkpoint**: Portability verified. Consumer repos without `plugin-shelf/` can run the workflow.

---

## Phase 8: User Story 6 — Graceful MCP-unavailable degradation (Priority: P3)

**Goal**: If the Obsidian MCP is unavailable at the moment of write, the step emits one stderr warning line, exits 0, and does not block the caller.

**Independent Test**: Simulate MCP unavailability (or mock it in the agent instruction test); seed a valid propose reflect output; run; assert exit 0, one-line warning in `write-proposal-mcp.txt`, no partial file.

### Implementation for User Story 6

- [ ] T030 [US6] [FR-015] In the `write-proposal-mcp` agent instruction (already modified in T016), add explicit handling for MCP-tool-unavailable: write exactly one line `warn: obsidian MCP unavailable; manifest improvement proposal not persisted` to the step output file `.wheel/outputs/propose-manifest-improvement-mcp.txt` and exit successfully.

### Tests for User Story 6

- [ ] T031 [US6] [FR-015] Write integration test `tests/integration/mcp-unavailable.sh` that — using an environment where the `mcp__claude_ai_obsidian-manifest__create_file` tool is disabled — seeds a valid propose reflect output, invokes the workflow, asserts exit 0, asserts the output file contains exactly the single warning line, asserts no file in `@inbox/open/`.

**Checkpoint**: All six user stories are complete. The sub-workflow is silent, specific, scope-bounded, wired, portable, and graceful.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and documentation.

- [ ] T032 [P] [FR-001..FR-020] Run ALL unit + integration tests from Phases 2–8. Confirm >=80% line coverage on the four new bash scripts.
- [ ] T033 [P] Update the project's CLAUDE.md active-technologies list if the `/update-agent-context.sh` run during planning missed anything specific to this feature. (Usually a no-op.)
- [ ] T034 Run `jq -r '.steps[] | select(.type=="command") | .command' plugin-shelf/workflows/propose-manifest-improvement.json plugin-kiln/workflows/*.json plugin-shelf/workflows/*.json | grep -F 'plugin-shelf/scripts/'` — expect empty output. Constitution rule "plugin portability NON-NEGOTIABLE".
- [ ] T035 Execute the quickstart.md recipe end-to-end manually (Sections 1–9). Record observations in `specs/manifest-improvement-subroutine/agent-notes/implementer.md`.
- [ ] T036 Run the PRD audit — verify every PRD FR (FR-1..FR-16) has a matching spec FR (FR-001..FR-020) AND a matching task above. Document any gap in `specs/manifest-improvement-subroutine/blockers.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies.
- **Phase 2 (Foundational)**: Blocks all user-story phases. T004–T007 must pass unit tests before any US phase begins. T008–T011 can run in parallel with T004–T007 (TDD-friendly — write tests first, then implementation) OR after — either order works.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Depends on Phase 2. Independent of Phase 3 — can proceed in parallel.
- **Phase 5 (US3)**: Depends on Phase 2. Independent of Phases 3–4.
- **Phase 6 (US4)**: Depends on Phases 3–5 (the sub-workflow must exist before callers reference it).
- **Phase 7 (US5)**: Depends on Phase 3 (workflow file must exist to be audited). Independent of Phases 4–6.
- **Phase 8 (US6)**: Depends on Phase 4 (same MCP agent step being extended).
- **Phase 9 (Polish)**: Depends on all prior phases.

### Within Each User Story

- Implementation tasks depend on Foundational (Phase 2) being complete.
- Tests depend on their implementation tasks being complete (or written first, TDD-style — either ordering is acceptable per constitution II).
- Agent-step instruction tasks for the SAME step (T013, T016, T017, T030 all modify `write-proposal-mcp` instruction) are SERIALIZED — the same file cannot be edited in parallel.

### Parallel Opportunities

- **Phase 2**: T004, T005, T006 write different bash scripts → parallelizable. T008, T009, T010 write different test files → parallelizable. T007 depends on T004–T006. T011 depends on T007.
- **Phase 6**: T023, T024, T025 edit different JSON files → parallelizable. T026 is independent (new file).
- **Phase 9**: T032, T033 are independent and parallelizable.

---

## Parallel Example: Phase 2

```bash
# Launch the three helper implementations together:
Task: "Implement plugin-shelf/scripts/validate-reflect-output.sh (T004)"
Task: "Implement plugin-shelf/scripts/derive-proposal-slug.sh (T005)"
Task: "Implement plugin-shelf/scripts/check-manifest-target-exists.sh (T006)"

# Launch the three unit-test files together:
Task: "Write tests/unit/validate-reflect-output.bats (T008)"
Task: "Write tests/unit/derive-proposal-slug.bats (T009)"
Task: "Write tests/unit/check-manifest-target-exists.bats (T010)"
```

---

## Implementation Strategy

### MVP (US1 + US2 + US3)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational) — all bash helpers pass unit tests.
3. Complete Phases 3, 4, 5 in any order (parallelizable).
4. **SELF-VALIDATE**: Run `tests/integration/silent-skip.sh`, `write-proposal.sh`, `out-of-scope.sh`, `hallucinated-current.sh`, `ungrounded-why.sh`.
5. MVP is now shippable as a standalone sub-workflow.

### Incremental

1. MVP ship → sub-workflow runnable standalone via `/wheel-run shelf:propose-manifest-improvement`.
2. Phase 6 → callers wired; feature now activates automatically on the three sync workflows.
3. Phase 7 → portability verified; safe for consumer repos.
4. Phase 8 → graceful MCP degradation.
5. Phase 9 → full polish.

---

## Notes

- [P] = different files, no dependency on another in-flight task.
- Every task references at least one FR for audit traceability.
- Same-file edits (`write-proposal-mcp` agent instruction: T013, T016, T017, T030) are serialized.
- Mark `[X]` immediately on completion — constitution VIII NON-NEGOTIABLE.
- Commit after each phase — constitution VIII.
- The contracts/interfaces.md file is authoritative; any signature change must update it FIRST.
