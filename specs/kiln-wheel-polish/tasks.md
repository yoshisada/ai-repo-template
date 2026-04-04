# Tasks: Kiln & Wheel Polish

**Input**: Design documents from `specs/kiln-wheel-polish/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md (required)

## Phase 1: Wheel Engine — `next` Field Support (FR-001–FR-007)

**Goal**: Steps can specify a `next` field to jump to a specific step instead of advancing linearly.

**Independent Test**: Create a test workflow with `next` fields and verify the engine follows them.

### Implementation

- [ ] T001 [US1] Add `resolve_next_index` function to `plugin-wheel/lib/dispatch.sh` — resolves `next` field to step index via `workflow_get_step_index`, defaults to `step_index + 1` if no `next` field. Returns resolved index. (FR-001, FR-002, FR-003, FR-006)

- [ ] T002 [US1] Modify `dispatch_command` in `plugin-wheel/lib/dispatch.sh` — replace hardcoded `$((step_index + 1))` cursor advance with `resolve_next_index` call. Apply to both the direct advance path and the command-chaining path. (FR-004)

- [ ] T003 [US1] Modify `dispatch_agent` in `plugin-wheel/lib/dispatch.sh` — replace hardcoded `$((step_index + 1))` cursor advance with `resolve_next_index` call. Apply to both the `stop` handler (working branch, output-complete path) and the `subagent_stop` handler. (FR-005)

- [ ] T004 [US1] Extend `workflow_validate_references` in `plugin-wheel/lib/workflow.sh` — add validation that checks all steps with a `next` field reference an existing step ID. Reuse the same `all_ids` array already built for branch target validation. (FR-007)

**Checkpoint**: A workflow with `next` fields should follow the specified step order instead of linear advancement. Existing workflows without `next` fields should behave identically.

---

## Phase 2: Wheel Engine — Terminal Step Cleanup (FR-008–FR-012)

**Goal**: Steps marked `terminal: true` automatically archive state.json and end the workflow.

**Independent Test**: Create a workflow with a terminal step and verify state.json is archived and removed.

### Implementation

- [ ] T005 [US2] Add `handle_terminal_step` function to `plugin-wheel/lib/dispatch.sh` — checks step JSON for `terminal: true`, archives state.json to `.wheel/history/success/` or `.wheel/history/failure/` based on step ID, removes state.json, sets cursor to total_steps. (FR-008, FR-009, FR-010)

- [ ] T006 [US2] Integrate `handle_terminal_step` into `dispatch_command` — after marking step done, check for terminal field before advancing cursor. If terminal, call `handle_terminal_step` and return. (FR-008)

- [ ] T007 [US2] Integrate `handle_terminal_step` into `dispatch_agent` — same integration in both `stop` (working/output-complete) and `subagent_stop` handlers. (FR-008)

- [ ] T008 [US2] Verify no-op guard in `plugin-wheel/hooks/stop.sh` and `plugin-wheel/hooks/post-tool-use.sh` — confirm that missing state.json is already handled silently (exit 0 with approve response). If not, downgrade the error to a silent no-op. (FR-011, FR-012)

**Checkpoint**: A workflow with `terminal: true` on a step should auto-archive and remove state.json when that step completes. Existing workflows should work identically.

---

## Phase 3: Kiln — /todo Skill (FR-013–FR-018)

**Goal**: Users can manage ad-hoc TODOs with `/todo`.

**Independent Test**: Run `/todo`, `/todo <text>`, `/todo done <N>`, `/todo clear` and verify `.kiln/todos.md` contents.

### Implementation

- [ ] T009 [US3] Create `plugin-kiln/skills/todo/prompt.md` — skill definition with frontmatter (name: todo, description), argument parsing for 4 modes (list, add, done N, clear), file creation on first use, date stamping. (FR-013, FR-014, FR-015, FR-016, FR-017, FR-018)

**Checkpoint**: `/todo` skill should be discoverable and functional for all 4 operations.

---

## Phase 4: UX Evaluator Path Fix + Cleanup (FR-019–FR-021)

**Goal**: Screenshots land in the correct directory; cleanup detects nested .kiln/ trees.

**Independent Test**: Check that the UX evaluator agent definition references absolute paths. Check that kiln-cleanup scans for nested .kiln/ dirs.

### Implementation

- [ ] T010 [P] [US4] Fix screenshot path in `plugin-kiln/agents/ux-evaluator.md` — change the "Screenshot directory" reference in the Input section to use absolute path `$(git rev-parse --show-toplevel)/.kiln/qa/screenshots/`. Also update Step 3a screenshot save paths. (FR-019, FR-020)

- [ ] T011 [P] [US4] Add nested `.kiln/` detection to `plugin-kiln/skills/kiln-cleanup/SKILL.md` — add a step between Step 2.5 and Step 3 that scans for `.kiln/` directories inside `.kiln/qa/` using `find .kiln/qa -name ".kiln" -type d`. In dry-run mode, list them. In delete mode, `rm -rf` each match. (FR-021)

**Checkpoint**: UX evaluator uses absolute paths. Cleanup skill detects and removes nested .kiln/ trees.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** (next field): No dependencies — can start immediately
- **Phase 2** (terminal): Depends on Phase 1 (uses `resolve_next_index` in terminal step flows, shares modified functions)
- **Phase 3** (todo): No dependencies on Phase 1/2 — can run in parallel with Phase 1
- **Phase 4** (path fix): No dependencies on Phase 1/2/3 — can run in parallel with Phase 1

### Parallel Opportunities

- T010 and T011 are marked [P] — different files, no dependencies
- Phase 3 and Phase 4 can run in parallel with Phases 1/2 (different plugins)
- Within Phase 1, T001 must complete before T002/T003 (they call the new function)
- T004 is independent of T001–T003 (different file, validation only)

### Agent Assignment (for build-prd pipeline)

- **impl-wheel**: Phase 1 (T001–T004) + Phase 2 (T005–T008) — all wheel engine changes
- **impl-kiln**: Phase 3 (T009) + Phase 4 (T010–T011) — all kiln plugin changes

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Commit after each completed phase
- All function signatures must match `contracts/interfaces.md`
