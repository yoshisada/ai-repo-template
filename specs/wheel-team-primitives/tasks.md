# Tasks: Wheel Team Primitives

**Input**: Design documents from `/specs/wheel-team-primitives/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: No test suite exists for the plugin. Testing is via workflow execution on consumer projects.

**Organization**: Tasks are grouped by user story to enable independent implementation. Phase 3 (US1/US2/US3) covers the step type handlers. Phase 4 (US5/US6) covers engine integration. Phase 5 (US4) covers failure resilience. Phase 6 (US7) covers cross-cutting polish.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Foundation for all step type handlers — state management functions that all handlers depend on.

- [X] T001 Add `state_set_team()` function to `plugin-wheel/lib/state.sh` — records team under `teams.{step_id}` with team_name and empty teammates map
- [X] T002 Add `state_get_team()` function to `plugin-wheel/lib/state.sh` — reads team metadata from state JSON by step_id
- [X] T003 Add `state_add_teammate()` function to `plugin-wheel/lib/state.sh` — adds teammate entry with task_id, agent_id, output_dir, status, assign payload
- [X] T004 Add `state_update_teammate_status()` function to `plugin-wheel/lib/state.sh` — updates a teammate's status with timestamp
- [X] T005 Add `state_get_teammates()` function to `plugin-wheel/lib/state.sh` — returns all teammate entries for a team
- [X] T006 Add `state_remove_team()` function to `plugin-wheel/lib/state.sh` — removes team entry from state (used by team-delete)

**Checkpoint**: All team state management functions exist. Step type handlers can now be implemented.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Wire the four new step types into the engine routing so handlers can be dispatched.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T007 Add `team-create|teammate|team-wait|team-delete` case branches in `dispatch_step()` in `plugin-wheel/lib/dispatch.sh` — each branch calls its corresponding `dispatch_*` function (stub implementations returning `{"decision": "approve"}`)
- [X] T008 Add team types to `engine_kickstart()` case statement in `plugin-wheel/lib/engine.sh` — `team-create|teammate|team-delete` set step to pending, `team-wait` is not kickstartable
- [X] T009 Add team types to `engine_handle_hook()` post_tool_use handler in `plugin-wheel/lib/engine.sh` — route `team-create`, `teammate`, `team-wait`, `team-delete` steps to dispatch_step
- [X] T010 Add team step reference validation in `workflow_validate_references()` in `plugin-wheel/lib/workflow.sh` — validate `team` field on teammate/team-wait/team-delete references a valid team-create step ID, validate `loop_from` references an existing step ID

**Checkpoint**: Engine recognizes all four types, routes hooks correctly, validates workflow JSON. Handlers are stubs.

---

## Phase 3: User Stories 1, 2, 3 — Step Type Handlers (Priority: P1)

**Goal**: Implement all four step type dispatch handlers in dispatch.sh.

**Independent Test**: Create a workflow JSON with team-create, 3 teammates, team-wait, and team-delete. Run it via `/wheel-run`. Verify all steps execute in order.

### US1 — Static Fan-Out (team-create + teammate)

- [X] T011 [US1] Implement `dispatch_team_create()` in `plugin-wheel/lib/dispatch.sh` — on stop hook when pending: inject instruction for orchestrator to call TeamCreate with team name (auto-generate from workflow name + step ID if omitted), mark working. On post_tool_use: detect TeamCreate completion, call state_set_team, mark done, advance cursor.
- [X] T012 [US1] Implement `dispatch_teammate()` static path in `plugin-wheel/lib/dispatch.sh` — on stop hook when pending: read team name from state, write context.json and assignment.json to output dir, inject instruction for orchestrator to spawn Agent with run_in_background and TaskCreate. Mark done after spawn instruction injected (fire-and-forget). Advance cursor.
- [X] T013 [US1] Add `context_write_teammate_files()` to `plugin-wheel/lib/context.sh` — writes context.json (combined outputs from context_from steps) and assignment.json (assign payload) to the teammate output directory

### US2 — Dynamic Fan-Out (loop_from)

- [X] T014 [US2] Implement `dispatch_teammate()` dynamic path (loop_from) in `plugin-wheel/lib/dispatch.sh` — when loop_from is present: read referenced step output, parse JSON array, apply max_agents cap (default 5), distribute entries round-robin, spawn one agent per group with unique name `{step-id}-{index}`, each receiving its grouped entries as assign payload

### US3 — Wait and Collect

- [X] T015 [US3] Implement `dispatch_team_wait()` in `plugin-wheel/lib/dispatch.sh` — on stop hook when pending: mark working. On each stop hook while working: read teammate statuses from state. If all done/failed: write summary JSON (total, completed, failed, per-teammate details), copy outputs to collect_to if set, mark done, advance cursor. If not all done: return block with progress status.
- [X] T016 [US3] Implement team-wait summary writer — generates summary JSON matching data-model.md schema (team_name, total, completed, failed, per-teammate name/status/output_dir/duration_seconds), writes to step output path

**Checkpoint**: Static fan-out, dynamic fan-out, and wait-collect all functional. Can run a complete team workflow.

---

## Phase 4: User Stories 5, 6 — Engine Integration (Priority: P2)

**Goal**: Team cleanup, cascade stop, and context passing.

**Independent Test**: Stop a running parent workflow while teammates are active. Verify cascade cleanup. Test context_from passing with synthetic step IDs.

### US5 — Team Cleanup and Cascade Stop

- [X] T017 [US5] Implement `dispatch_team_delete()` in `plugin-wheel/lib/dispatch.sh` — on stop hook when pending: inject instruction for orchestrator to send shutdown to all teammates and call TeamDelete. Handle force-termination if teammates still running. On post_tool_use: detect TeamDelete completion, call state_remove_team, mark done, advance cursor.
- [X] T018 [US5] Add cascade stop for team agents in deactivate.sh handler in `plugin-wheel/hooks/post-tool-use.sh` — after stopping parent workflows, read teams key from stopped state files, for each team with running teammates log the team for cleanup. Note: actual agent shutdown happens via Claude Code's built-in cascade when the parent agent stops.
- [X] T019 [US5] Ensure idempotency — team-create on existing team is no-op, team-delete on deleted team is no-op, re-running team-wait after completion is no-op

### US6 — Sub-Workflow Context Passing

- [X] T020 [US6] Add `context_resolve_synthetic()` to `plugin-wheel/lib/context.sh` — resolves `_context` and `_assignment` synthetic step IDs by reading context.json and assignment.json from the current agent's output directory
- [X] T021 [US6] Modify `context_build()` in `plugin-wheel/lib/context.sh` — when encountering `_context` or `_assignment` in context_from array, delegate to context_resolve_synthetic instead of looking up state step outputs

**Checkpoint**: Full team lifecycle works including cleanup, cascade stop, and context passing.

---

## Phase 5: User Story 4 — Failure Resilience (Priority: P2)

**Goal**: Ensure partial failures don't break workflows.

**Independent Test**: Create a workflow where 1 of 3 teammates is designed to fail. Verify team-wait reports partial results and workflow continues.

- [X] T022 [US4] Ensure `dispatch_team_wait()` handles mixed success/failure — team-wait MUST NOT fail when some teammates fail. Summary must report accurate completed/failed counts. Downstream steps receive the summary and decide how to handle failures.
- [X] T023 [US4] Handle edge cases in `dispatch_teammate()` — empty loop_from array (0 items spawns 0 agents, team-wait immediately completes), invalid JSON in loop_from output (mark step failed with error), max_agents <= 0 (use default 5)

**Checkpoint**: Failure resilience verified. Partial results collected correctly.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validation, edge cases, and documentation.

- [ ] T024 [P] Validate all team operations are idempotent — run team-create twice with same name (no error), run team-delete on already-deleted team (no error), run team-wait when no teammates spawned (immediate completion with 0/0 summary)
- [ ] T025 [P] Verify existing workflow types unchanged — run a workflow with command, agent, workflow, and branch steps to confirm no regressions from the new case branches
- [ ] T026 Add team step types to engine_handle_hook stop handler in `plugin-wheel/lib/engine.sh` — ensure stop hook routes team-create, teammate, team-wait, team-delete to dispatch_step (same pattern as agent steps)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — state functions first
- **Foundational (Phase 2)**: Depends on Phase 1 — engine routing stubs
- **Step Type Handlers (Phase 3)**: Depends on Phase 2 — real handler implementations
- **Engine Integration (Phase 4)**: Depends on Phase 2 — can run in parallel with Phase 3
- **Failure Resilience (Phase 5)**: Depends on Phase 3 (needs handlers to exist)
- **Polish (Phase 6)**: Depends on Phases 3, 4, 5

### User Story Dependencies

- **US1 (Static Fan-Out)**: Depends on Phase 2 (foundational) — no other story dependencies
- **US2 (Dynamic Fan-Out)**: Depends on US1 T012 (static teammate handler exists, adds loop_from path)
- **US3 (Wait and Collect)**: Depends on Phase 2 — independent of US1/US2 for implementation, but needs teammates to test
- **US4 (Failure Resilience)**: Depends on US3 (wait handler must exist)
- **US5 (Team Cleanup)**: Depends on Phase 2 — independent
- **US6 (Context Passing)**: Depends on US1 T013 (context_write_teammate_files must exist)

### File Ownership (for parallel agents)

- **impl-step-types agent**: `plugin-wheel/lib/dispatch.sh` (T007, T011-T017, T019, T022-T023)
- **impl-engine agent**: `plugin-wheel/lib/state.sh` (T001-T006), `plugin-wheel/lib/engine.sh` (T008-T009, T026), `plugin-wheel/lib/context.sh` (T013, T020-T021), `plugin-wheel/lib/workflow.sh` (T010), `plugin-wheel/hooks/post-tool-use.sh` (T018)

### Parallel Opportunities

- Phase 1: T001-T006 can all run in parallel (separate functions in state.sh, but same file — serialize)
- Phase 2: T007-T010 touch different files — T007 (dispatch.sh), T008-T009 (engine.sh), T010 (workflow.sh) can partially parallel
- Phase 3: T011-T012 (US1) and T015-T016 (US3) touch different logical sections — can parallel if separate agents own separate function blocks
- Phase 4 and Phase 3 can run in parallel (different files)

---

## Implementation Strategy

### MVP First (US1 — Static Fan-Out)

1. Complete Phase 1: State management functions
2. Complete Phase 2: Engine routing + validation stubs
3. Complete Phase 3 US1: team-create + teammate static handlers
4. Verify: A workflow with team-create → teammate → team-wait → team-delete runs end-to-end

### Incremental Delivery

1. Setup + Foundational → Engine recognizes team types
2. US1 (Static Fan-Out) → 3 teammates can be spawned
3. US3 (Wait and Collect) → Results are collected
4. US2 (Dynamic Fan-Out) → loop_from works
5. US5 (Cleanup + Cascade) → Clean shutdown
6. US6 (Context Passing) → Teammates receive context
7. US4 (Failure Resilience) → Partial failures handled
8. Polish → Idempotency, regression checks

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All handlers follow the existing dispatch pattern: read state → check status → act → mark done → advance cursor
- The teammate step is fire-and-forget: it injects the spawn instruction and advances immediately
- The team-wait step blocks: it checks status on every hook invocation until all done
- File ownership split between impl-step-types (dispatch.sh) and impl-engine (state.sh, engine.sh, context.sh, workflow.sh, post-tool-use.sh)
