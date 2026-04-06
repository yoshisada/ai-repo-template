# Tasks: Wheel Per-Agent State Files

**Input**: Design documents from `specs/wheel-per-agent-state/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md (required)

## Phase 1: Core Library Changes

**Purpose**: Update the foundational libraries to support per-agent state filenames.

- [X] T001 [US2] Replace `guard_check` with `resolve_state_file` in `plugin-wheel/lib/guard.sh`. The new function takes `state_dir` and `hook_input_json`, extracts session_id and agent_id, checks for `state_{session_id}_{agent_id}.json` then falls back to `state_{session_id}.json`, performs first-hook rename if needed, and returns the resolved path. (FR-003, FR-004, FR-005)
- [X] T002 [US2] Update `state_init` in `plugin-wheel/lib/state.sh` to accept `state_dir` and `session_id` instead of `state_file`. It constructs the filename as `state_{session_id}.json`, sets `owner_session_id` in the JSON, and leaves `owner_agent_id` empty. (FR-011)
- [X] T003 [US1] Update `engine_init` in `plugin-wheel/lib/engine.sh` to accept `state_file` (resolved path) as second param instead of `state_dir`. Remove hardcoded `STATE_FILE="${STATE_DIR}/state.json"`. Set `STATE_DIR` from dirname of state_file. Do NOT create state if missing (hooks only run when state exists). (FR-010)

**Checkpoint**: Core libraries support per-agent state filenames. Hooks and skills can now be updated.

---

## Phase 2: Hook Updates

**Purpose**: Update all 6 hooks to resolve state files from hook input instead of hardcoding `.wheel/state.json`.

- [X] T004 [P] [US3] Update `plugin-wheel/hooks/stop.sh` — replace hardcoded `state.json` check with `resolve_state_file` preamble. Remove `guard_check` call. Pass resolved state file to `engine_init`. (FR-004)
- [X] T005 [P] [US3] Update `plugin-wheel/hooks/post-tool-use.sh` — same pattern as T004. (FR-004)
- [X] T006 [P] [US3] Update `plugin-wheel/hooks/subagent-start.sh` — same pattern as T004. (FR-004)
- [X] T007 [P] [US3] Update `plugin-wheel/hooks/subagent-stop.sh` — same pattern as T004. (FR-004)
- [X] T008 [P] [US3] Update `plugin-wheel/hooks/teammate-idle.sh` — same pattern as T004. (FR-004)
- [X] T009 [P] [US3] Update `plugin-wheel/hooks/session-start.sh` — same pattern as T004. (FR-004)

**Checkpoint**: All hooks resolve per-agent state files. Concurrent agents each find their own state.

---

## Phase 3: Skill Updates

**Purpose**: Update wheel skills to work with per-agent state filenames.

- [ ] T010 [US2] Update `plugin-wheel/skills/wheel-run/SKILL.md` — obtain session_id, pass to `state_init`, check for existing `state_{session_id}*.json` before creating, use session_id-based filename for kickstart. (FR-002, FR-007, FR-010)
- [ ] T011 [US4] Update `plugin-wheel/skills/wheel-status/SKILL.md` — glob `state_*.json`, display all active workflows with session/agent IDs. (FR-008)
- [ ] T012 [US4] Update `plugin-wheel/skills/wheel-stop/SKILL.md` — glob `state_*.json`, support optional target identifier, archive each stopped file to `.wheel/history/`. (FR-009)

**Checkpoint**: All skills work with per-agent state files. Feature is functionally complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** (T001-T003): No external dependencies. T001 and T002 can run in parallel (different files). T003 depends on understanding T001's output but touches a different file.
- **Phase 2** (T004-T009): Depends on Phase 1 completion (T001 must be done for `resolve_state_file` to exist). All 6 hook tasks are independent of each other and can run in parallel.
- **Phase 3** (T010-T012): Depends on Phase 1 completion (T002 for new `state_init` signature, T003 for new `engine_init` signature). T010-T012 are independent of each other.

### Parallel Opportunities

- T001 and T002 can run in parallel (different files: guard.sh vs state.sh)
- T004-T009 can all run in parallel (different hook files)
- T010-T012 can all run in parallel (different skill files)

## Implementation Strategy

1. Complete Phase 1 (T001-T003) — core library changes
2. Complete Phase 2 (T004-T009) — hook updates (all parallel)
3. Complete Phase 3 (T010-T012) — skill updates (all parallel)
4. Manual verification: start two workflows, confirm isolation

## Notes

- No test suite exists for the plugin. Verification is manual.
- dispatch.sh, workflow.sh, context.sh, lock.sh are NOT modified — they already receive state_file as a parameter.
- The `guard_check` function is fully replaced by `resolve_state_file`. The old guard.sh file is rewritten, not appended to.
