# Tasks: Wheel — Hook-based Workflow Engine Plugin

**Input**: Design documents from `specs/wheel/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md (required)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Plugin Structure)

**Purpose**: Create the plugin directory structure and package configuration

- [X] T001 [P] [US7] Create `plugin-wheel/.claude-plugin/plugin.json` with plugin manifest per contracts/interfaces.md
- [X] T002 [P] [US7] Create `plugin-wheel/.claude-plugin/marketplace.json` with distribution config
- [X] T003 [P] [US7] Create `plugin-wheel/package.json` for npm package `@yoshisada/wheel` (version 0.1.0)
- [X] T004 [P] [US7] Create `plugin-wheel/scaffold/settings-hooks.json` defining all 6 hook event configurations

**Checkpoint**: Plugin skeleton exists, no logic yet

---

## Phase 2: Core Engine — State Management (FR-002)

**Purpose**: Build the state persistence layer that all other modules depend on

- [X] T005 [US1] Implement `plugin-wheel/lib/state.sh` with all functions per contracts/interfaces.md: `state_read`, `state_write` (atomic tmp+rename), `state_init`, `state_get_cursor`, `state_set_cursor`, `state_get_step_status`, `state_set_step_status`, `state_set_step_output`, `state_get_step_output`, `state_append_command_log`, `state_get_command_log`
- [X] T006 [US3] Add parallel agent state functions to `plugin-wheel/lib/state.sh`: `state_get_agent_status`, `state_set_agent_status`

**Checkpoint**: State module complete — can read/write/query state.json atomically

---

## Phase 3: Core Engine — Workflow Parser and Lock (FR-010, FR-012)

**Purpose**: Workflow loading/validation and atomic locking

- [ ] T007 [P] [US1] Implement `plugin-wheel/lib/workflow.sh` with all functions per contracts/interfaces.md: `workflow_load`, `workflow_get_steps`, `workflow_get_step`, `workflow_get_step_by_id`, `workflow_get_step_index`, `workflow_step_count`, `workflow_validate_references`
- [ ] T008 [P] [US3] Implement `plugin-wheel/lib/lock.sh` with all functions per contracts/interfaces.md: `lock_acquire`, `lock_release`, `lock_clean_all`

**Checkpoint**: Can load workflows, validate references, and acquire/release locks

---

## Phase 4: Core Engine — Dispatch and Context (FR-003, FR-019, FR-024-028)

**Purpose**: Step type routing, context injection, and the main engine module

- [ ] T009 [US1] Implement `plugin-wheel/lib/context.sh` with all functions per contracts/interfaces.md: `context_build`, `context_capture_output`, `context_subagent_start`
- [ ] T010 [US1] Implement `plugin-wheel/lib/dispatch.sh` — `dispatch_step` (router) and `dispatch_agent` (FR-003)
- [ ] T011 [US1] Add `dispatch_command` to `plugin-wheel/lib/dispatch.sh` (FR-019/020/021) — execute shell command, record output, support chaining via exec
- [ ] T012 [US3] Add `dispatch_parallel` to `plugin-wheel/lib/dispatch.sh` (FR-009) — fan-out agent instructions
- [ ] T013 [US4] Add `dispatch_approval` to `plugin-wheel/lib/dispatch.sh` (FR-013) — gate until approved
- [ ] T014 [US5] Add `dispatch_branch` to `plugin-wheel/lib/dispatch.sh` (FR-024) — evaluate condition, jump to target
- [ ] T015 [US5] Add `dispatch_loop` to `plugin-wheel/lib/dispatch.sh` (FR-025/026) — repeat substep with condition and max_iterations
- [ ] T016 [US1] Implement `plugin-wheel/lib/engine.sh` with all functions per contracts/interfaces.md: `engine_init`, `engine_current_step`, `engine_handle_hook` — sources all lib modules

**Checkpoint**: Full engine logic complete — all step types dispatchable

---

## Phase 5: Hook Handlers (FR-004 through FR-008, FR-022)

**Purpose**: Wire Claude Code hooks to the engine

- [ ] T017 [P] [US1] Implement `plugin-wheel/hooks/stop.sh` (FR-004) — read stdin JSON, source engine, call `engine_handle_hook("stop", input)`, output response JSON
- [ ] T018 [P] [US1] Implement `plugin-wheel/hooks/teammate-idle.sh` (FR-005) — gate agents with step instruction or allow idle
- [ ] T019 [P] [US1] Implement `plugin-wheel/hooks/subagent-start.sh` (FR-006) — inject context via `context_subagent_start`
- [ ] T020 [P] [US1] Implement `plugin-wheel/hooks/subagent-stop.sh` (FR-007) — mark agent done, check fan-in, advance step
- [ ] T021 [P] [US2] Implement `plugin-wheel/hooks/session-start.sh` (FR-008) — reload state.json on resume, inject resume instructions
- [ ] T022 [P] [US6] Implement `plugin-wheel/hooks/post-tool-use.sh` (FR-022/023) — log Bash commands to step command_log

**Checkpoint**: All 6 hooks wired — engine is drivable by Claude Code

---

## Phase 6: Scaffold and Init (FR-014, FR-015, FR-016)

**Purpose**: Consumer project scaffolding and npm packaging

- [X] T023 [US7] Implement `plugin-wheel/bin/init.mjs` with `init()` and `update()` functions per contracts/interfaces.md — create .wheel/, workflows/, merge hooks into .claude/settings.json
- [X] T024 [P] [US7] Create `plugin-wheel/scaffold/example-workflow.json` — a 3-step example workflow (1 command step + 1 agent step + 1 command step) that proves linear execution end-to-end
- [X] T025 [P] [US7] Create `plugin-wheel/workflows/example.json` — same example workflow shipped with the plugin for reference

**Checkpoint**: `npx @yoshisada/wheel init` works in a consumer project

---

## Phase 7: Integration Testing

**Purpose**: Verify the engine works end-to-end with the example workflow

- [ ] T026 [US1] Create `tests/integration/test-linear-workflow.sh` — run the example 3-step workflow, assert state.json shows all steps `done` in order
- [ ] T027 [US2] Create `tests/integration/test-resume.sh` — run a workflow, simulate crash by truncating state to step 2, resume session, verify step 3 executes
- [ ] T028 [US1] Create `tests/integration/test-command-step.sh` — run a workflow with command steps, verify output and exit code in state.json
- [ ] T029 [US5] Create `tests/integration/test-branch-loop.sh` — run a workflow with branch and loop steps, verify correct control flow

**Checkpoint**: All core user stories verified via integration tests

---

## Phase 8: Polish

**Purpose**: Documentation and final packaging

- [ ] T030 [P] Create `plugin-wheel/README.md` with usage instructions, workflow format reference, and getting started guide
- [X] T031 [P] Add `.gitignore` entries for `.wheel/state.json` and `.wheel/.locks/` to `plugin-wheel/scaffold/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — can start immediately
- **Phase 2 (State)**: Depends on Phase 1 (needs directory structure)
- **Phase 3 (Workflow + Lock)**: Depends on Phase 1; can run in parallel with Phase 2
- **Phase 4 (Dispatch + Context + Engine)**: Depends on Phases 2 and 3 (sources all lib modules)
- **Phase 5 (Hooks)**: Depends on Phase 4 (hooks call engine functions)
- **Phase 6 (Scaffold)**: Depends on Phase 5 (needs hook scripts to exist for settings-hooks.json references)
- **Phase 7 (Testing)**: Depends on Phases 5 and 6
- **Phase 8 (Polish)**: Depends on Phase 7

### Parallel Opportunities

- Phase 1: All T001-T004 can run in parallel (different files)
- Phase 2: T005 before T006 (T006 extends the same file)
- Phase 3: T007 and T008 can run in parallel (different files)
- Phase 4: T009 first, then T010-T016 sequentially (same file for T010-T015, T016 sources all)
- Phase 5: All T017-T022 can run in parallel (different files)
- Phase 6: T023 first, T024-T025 in parallel
- Phase 7: All tests can run in parallel (different files)
- Phase 8: All tasks in parallel

### Agent Assignment Recommendation

- **impl-engine** (Phases 2-5): T005-T022 — core engine, all lib modules, all hooks
- **impl-plugin** (Phases 1, 6-8): T001-T004, T023-T031 — plugin structure, scaffold, tests, docs
