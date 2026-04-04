# Tasks: Wheel Skill-Based Activation

**Input**: Design documents from `specs/wheel-skill-activation/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md (required)

## Phase 1: Library Changes (Blocking Prerequisites)

**Purpose**: Add the `workflow_file` field to state.json and the unique-ID validator, so skills and hooks can use them.

- [ ] T001 [US1] Add `workflow_validate_unique_ids()` to `plugin-wheel/lib/workflow.sh` — validates all step IDs are unique per contracts/interfaces.md. Params: `$1 = workflow JSON string`. Exit 0 if unique, 1 if duplicates (error on stderr).
- [ ] T002 [US1] Modify `state_init()` in `plugin-wheel/lib/state.sh` — accept optional `$3 = workflow_file` parameter and include `"workflow_file"` in the generated state.json per contracts/interfaces.md.

**Checkpoint**: `workflow_validate_unique_ids()` and updated `state_init()` are available for skills and hooks.

---

## Phase 2: Hook Guard Clause Updates (FR-004, FR-005)

**Purpose**: Replace auto-discovery logic in all hooks with the state.json existence check.

- [ ] T003 [P] [US1] Rewrite `plugin-wheel/hooks/stop.sh` — replace lines 23-33 (auto-discovery + WHEEL_WORKFLOW fallback) with state.json guard clause per contracts/interfaces.md. Read `workflow_file` from state.json instead of scanning `workflows/`. Keep engine_init and engine_handle_hook calls.
- [ ] T004 [P] [US1] Rewrite `plugin-wheel/hooks/teammate-idle.sh` — same guard clause pattern as T003. Remove auto-discovery, add state.json guard, read workflow_file from state.json.
- [ ] T005 [P] [US1] Rewrite `plugin-wheel/hooks/subagent-start.sh` — same guard clause pattern. Remove auto-discovery. Note: this hook has custom context injection logic after engine_init; preserve that.
- [ ] T006 [P] [US1] Rewrite `plugin-wheel/hooks/subagent-stop.sh` — same guard clause pattern as T003.
- [ ] T007 [P] [US1] Rewrite `plugin-wheel/hooks/session-start.sh` — same guard clause pattern. This hook already checks for state.json existence; simplify by removing auto-discovery and making the state.json check the FIRST thing (before reading stdin).
- [ ] T008 [P] [US1] Rewrite `plugin-wheel/hooks/post-tool-use.sh` — same guard but use `exit 0` instead of JSON output (PostToolUse hooks don't return decisions). Remove auto-discovery. This hook already has a state.json check; move it to the top and remove the workflow file lookup.

**Checkpoint**: All hooks pass through silently when `.wheel/state.json` does not exist. No workflow auto-discovery remains.

---

## Phase 3: User Story 1 — /wheel-run Skill (Priority: P1)

**Goal**: Create the `/wheel-run` skill that validates a workflow and creates state.json to activate hooks.

**Independent Test**: Run `/wheel-run example` — verify `.wheel/state.json` is created, hooks begin intercepting.

- [ ] T009 [US1] Create `plugin-wheel/skills/wheel-run/SKILL.md` — skill definition per contracts/interfaces.md. Must instruct the LLM to: (1) check for existing state.json and refuse if present (FR-007), (2) resolve `workflows/$ARGUMENTS.json`, (3) source engine libs and call `workflow_load()` + `workflow_validate_unique_ids()` for validation (FR-006), (4) call `state_init()` with the workflow file path, (5) output the first step info.

**Checkpoint**: `/wheel-run example` creates state.json and hooks activate.

---

## Phase 4: User Story 2 — /wheel-stop Skill (Priority: P2)

**Goal**: Create the `/wheel-stop` skill that removes state.json to deactivate hooks.

**Independent Test**: After `/wheel-run example`, run `/wheel-stop` — verify state.json is removed and hooks pass through.

- [ ] T010 [US2] Create `plugin-wheel/skills/wheel-stop/SKILL.md` — skill definition per contracts/interfaces.md. Must instruct the LLM to: (1) check if state.json exists, (2) archive to `.wheel/history/`, (3) remove state.json, (4) confirm deactivation.

**Checkpoint**: `/wheel-stop` removes state.json, hooks become dormant.

---

## Phase 5: User Story 3 — /wheel-status Skill (Priority: P3)

**Goal**: Create the `/wheel-status` skill that displays workflow progress.

**Independent Test**: Start a workflow, run `/wheel-status` — verify it shows name, step, progress, elapsed time.

- [ ] T011 [US3] Create `plugin-wheel/skills/wheel-status/SKILL.md` — skill definition per contracts/interfaces.md. Must instruct the LLM to: (1) check if state.json exists, (2) read and parse state.json with jq, (3) display formatted status output.

**Checkpoint**: `/wheel-status` shows accurate workflow progress.

---

## Phase 6: Package Config

**Purpose**: Ensure skills are included in the published npm package.

- [ ] T012 [P] Add `"skills/"` to the `files` array in `plugin-wheel/package.json`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** (lib changes): No dependencies — start immediately
- **Phase 2** (hooks): Depends on T002 (state_init with workflow_file) because hooks read workflow_file from state.json
- **Phase 3** (/wheel-run): Depends on Phase 1 (T001 + T002) for validation and state_init
- **Phase 4** (/wheel-stop): No dependency on Phase 1-3 (reads/removes state.json directly)
- **Phase 5** (/wheel-status): No dependency on Phase 1-3 (reads state.json directly)
- **Phase 6** (package.json): No dependencies

### Parallel Opportunities

- T003-T008 are all [P] — all six hooks can be modified in parallel
- T010, T011, T012 are independent of each other and can run in parallel
- Phase 4, 5, 6 can start as soon as Phase 1 is done (they don't need Phase 2 or 3)

### Within Each Phase

- Phase 1: T001 and T002 are independent (different files) — can run in parallel
- Phase 2: All tasks are [P] — different files, no dependencies
- Phase 3-5: Single task each
