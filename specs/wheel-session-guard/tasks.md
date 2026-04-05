# Tasks: Wheel Session Guard

**Input**: Design documents from `specs/wheel-session-guard/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not requested in spec. No automated test framework for shell hooks in this plugin repo.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No setup needed — all changes are modifications to existing files in `plugin-wheel/`. No new project structure or dependencies.

*(No tasks in this phase)*

---

## Phase 2: Foundational (Guard Library + State Schema)

**Purpose**: Create the guard function and extend state.json schema. MUST complete before any hook integration.

- [X] T001 Create shared guard function `guard_check` in `plugin-wheel/lib/guard.sh` per contracts/interfaces.md — reads owner fields from state.json, extracts session_id/agent_id from hook input, implements first-hook stamping when owner fields are empty, returns 0 (owner) or 1 (non-owner)
- [X] T002 Modify `state_init` in `plugin-wheel/lib/state.sh` to include `owner_session_id: ""` and `owner_agent_id: ""` in the initial state JSON object
- [X] T003 Add `source "${WHEEL_LIB_DIR}/guard.sh"` to the module loading block in `plugin-wheel/lib/engine.sh`

**Checkpoint**: guard.sh exists with guard_check function, state_init produces ownership fields, engine.sh sources guard.sh

---

## Phase 3: User Story 1 — Workflow Isolation in Multi-Agent Pipelines (Priority: P1)

**Goal**: Hook events from non-owner agents pass through without touching workflow state.

**Independent Test**: Start a workflow, then manually invoke a hook script with a different session_id in the hook input JSON. Verify pass-through response and unmodified state.json.

### Implementation for User Story 1

- [X] T004 [P] [US1] Add guard call to `plugin-wheel/hooks/stop.sh` — after `engine_init` succeeds, call `guard_check "$STATE_FILE" "$HOOK_INPUT"` and exit with `{"decision": "approve"}` if non-owner
- [X] T005 [P] [US1] Add guard call to `plugin-wheel/hooks/post-tool-use.sh` — after `engine_init` succeeds, call `guard_check "$STATE_FILE" "$HOOK_INPUT"` and exit with `{"hookEventName": "PostToolUse"}` if non-owner
- [X] T006 [P] [US1] Add guard call to `plugin-wheel/hooks/subagent-start.sh` — after `engine_init` succeeds but before inline context logic, call `guard_check "$STATE_FILE" "$HOOK_INPUT"` and exit with `{"decision": "approve"}` if non-owner
- [X] T007 [P] [US1] Add guard call to `plugin-wheel/hooks/subagent-stop.sh` — after `engine_init` succeeds, call `guard_check "$STATE_FILE" "$HOOK_INPUT"` and exit with `{"decision": "approve"}` if non-owner
- [X] T008 [P] [US1] Add guard call to `plugin-wheel/hooks/teammate-idle.sh` — after `engine_init` succeeds, call `guard_check "$STATE_FILE" "$HOOK_INPUT"` and exit with `{"decision": "approve"}` if non-owner
- [X] T009 [P] [US1] Add guard call to `plugin-wheel/hooks/session-start.sh` — after `engine_init` succeeds, call `guard_check "$STATE_FILE" "$HOOK_INPUT"` and exit with `{"decision": "approve"}` if non-owner

**Checkpoint**: All 6 hooks call guard_check. Non-owner events get pass-through responses. Owner events proceed normally.

---

## Phase 4: User Story 2 — Ownership Stamping at Workflow Start (Priority: P1)

**Goal**: First hook event stamps ownership into state.json.

**Independent Test**: Run `/wheel-run` to create state.json, then trigger a hook event. Verify state.json gains `owner_session_id` and `owner_agent_id` matching the hook input.

### Implementation for User Story 2

*(Already implemented by T001 — guard_check handles first-hook stamping as part of the guard logic. No additional tasks needed.)*

**Checkpoint**: After `/wheel-run` + first hook event, state.json has non-empty owner_session_id.

---

## Phase 5: User Story 3 — Status and Stop from Any Session (Priority: P2)

**Goal**: `/wheel-status` and `/wheel-stop` work from any agent regardless of ownership.

**Independent Test**: Start a workflow, then run `/wheel-status` and `/wheel-stop` from a different session. Verify both succeed.

### Implementation for User Story 3

*(No implementation tasks needed — `/wheel-status` and `/wheel-stop` are skills, not hooks. They read/write state.json directly and never pass through the hook guard. This is confirmed in contracts/interfaces.md.)*

**Checkpoint**: Status and stop skills work unchanged from any agent.

---

## Phase 6: User Story 4 — Shared Guard Function (Priority: P2)

**Goal**: Guard logic in a single shared file, not duplicated across hooks.

**Independent Test**: Verify guard_check is defined in exactly one file (lib/guard.sh) and all 6 hooks call it.

### Implementation for User Story 4

*(Already implemented by T001 (creates guard.sh) and T004-T009 (hooks call guard_check). No additional tasks needed.)*

**Checkpoint**: `grep -r "guard_check" plugin-wheel/` shows lib/guard.sh as definition, 6 hooks as callers.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and verification.

- [ ] T010 Update `plugin-wheel/skills/wheel-run/SKILL.md` to document that ownership is stamped by the first hook event after state creation, per FR-004
- [ ] T011 Verify end-to-end: run `/wheel-run`, confirm state.json has empty owner fields, trigger a hook event, confirm owner fields are stamped, trigger a hook event with different session_id, confirm pass-through

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: No dependencies — start immediately
- **Phase 3 (US1 - Hook Integration)**: Depends on Phase 2 completion (T001-T003 must be done)
- **Phase 4 (US2)**: No additional tasks — covered by T001
- **Phase 5 (US3)**: No additional tasks — skills are exempt
- **Phase 6 (US4)**: No additional tasks — covered by T001 + T004-T009
- **Phase 7 (Polish)**: Depends on Phase 3 completion

### Within Phase 2

- T001, T002, T003 can run sequentially (T003 depends on T001 existing)

### Within Phase 3

- T004, T005, T006, T007, T008, T009 are all [P] — they modify different files and can run in parallel

### Parallel Opportunities

```
Phase 2: T001 → T002 → T003 (sequential, all in lib/)

Phase 3 (all parallel — different hook files):
  T004 (stop.sh) | T005 (post-tool-use.sh) | T006 (subagent-start.sh)
  T007 (subagent-stop.sh) | T008 (teammate-idle.sh) | T009 (session-start.sh)

Phase 7: T010 → T011 (sequential)
```

---

## Implementation Strategy

### MVP First (Phase 2 + Phase 3)

1. Complete Phase 2: Create guard.sh, update state.sh, update engine.sh
2. Complete Phase 3: Add guard calls to all 6 hooks
3. **SELF-VALIDATE**: Run a workflow and verify guard behavior
4. All user stories are satisfied after Phase 3

### Incremental Delivery

1. T001-T003 → Guard infrastructure ready
2. T004-T009 → All hooks guarded (core feature complete)
3. T010-T011 → Documentation and verification

---

## Notes

- Total tasks: 11
- Phase 2 (Foundational): 3 tasks
- Phase 3 (US1 — Hook Integration): 6 tasks (all parallelizable)
- Phase 7 (Polish): 2 tasks
- User Stories 2, 3, 4 require no additional tasks — they are satisfied by the foundational guard and hook integration work
- All 6 hook tasks (T004-T009) are parallelizable — each modifies a different file
