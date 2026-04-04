# Feature Specification: Wheel Skill-Based Activation

**Feature Branch**: `build/wheel-skill-activation-20260404`  
**Created**: 2026-04-04  
**Status**: Draft  
**Input**: PRD at `docs/features/2026-04-04-wheel-skill-activation/PRD.md`

## User Scenarios & Testing

### User Story 1 - Start a Workflow on Demand (Priority: P1)

As a developer with wheel installed, I want to explicitly start a workflow via `/wheel-run <name>` so that wheel hooks don't interfere with normal Claude Code usage.

**Why this priority**: This is the core activation gate. Without it, wheel hijacks every session. This single change makes wheel usable in practice.

**Independent Test**: Run `/wheel-run example` in a project with `workflows/example.json`. Verify `.wheel/state.json` is created and the Stop hook begins injecting workflow instructions.

**Acceptance Scenarios**:

1. **Given** a project with wheel installed and `workflows/example.json` present, **When** I run `/wheel-run example`, **Then** `.wheel/state.json` is created with `status: "running"`, `cursor: 0`, and the workflow name matching `example-workflow`.
2. **Given** no `.wheel/state.json` exists, **When** the Stop hook fires, **Then** it outputs `{"decision": "allow"}` and exits immediately (no workflow interception).
3. **Given** `/wheel-run example` has been executed, **When** the Stop hook fires, **Then** it reads `.wheel/state.json` and injects the current step instruction (existing engine behavior).
4. **Given** `.wheel/state.json` already exists (a workflow is running), **When** I run `/wheel-run example`, **Then** the skill refuses with a message suggesting `/wheel-stop` or `/wheel-status`.
5. **Given** a workflow JSON with duplicate step IDs, **When** I run `/wheel-run bad-workflow`, **Then** the skill reports the validation error and does not create state.json.
6. **Given** a workflow JSON with a `context_from` reference to a nonexistent step ID, **When** I run `/wheel-run bad-refs`, **Then** the skill reports the invalid reference and does not create state.json.

---

### User Story 2 - Stop a Running Workflow (Priority: P2)

As a developer, I want to stop a running workflow via `/wheel-stop` so I can return to normal Claude Code usage without restarting my session.

**Why this priority**: Paired with start, this provides the on/off switch. Less critical than start because you can always restart the session, but important for smooth UX.

**Independent Test**: Start a workflow with `/wheel-run example`, then run `/wheel-stop`. Verify `.wheel/state.json` is removed and the next Stop hook passes through.

**Acceptance Scenarios**:

1. **Given** a running workflow (`.wheel/state.json` exists), **When** I run `/wheel-stop`, **Then** `.wheel/state.json` is removed and hooks immediately become dormant.
2. **Given** a running workflow, **When** I run `/wheel-stop`, **Then** the workflow log is archived to `.wheel/history/<workflow-name>-<timestamp>.json`.
3. **Given** no workflow is running (no `.wheel/state.json`), **When** I run `/wheel-stop`, **Then** the skill reports "No workflow is currently running."

---

### User Story 3 - Check Workflow Progress (Priority: P3)

As a developer, I want to check the status of a running workflow via `/wheel-status` so I know which step is active and what has been completed.

**Why this priority**: Nice-to-have observability. The workflow runs without this, but it helps debugging and monitoring.

**Independent Test**: Start a workflow, advance a step, then run `/wheel-status`. Verify it shows the workflow name, current step, progress fraction, and elapsed time.

**Acceptance Scenarios**:

1. **Given** a running workflow at step 2 of 3, **When** I run `/wheel-status`, **Then** I see: workflow name, current step ID, step status, progress (2/3), and elapsed time since workflow start.
2. **Given** a running workflow with command log entries, **When** I run `/wheel-status`, **Then** the last command log entry for the current step is displayed.
3. **Given** no workflow is running, **When** I run `/wheel-status`, **Then** the skill reports "No workflow is currently running."

---

### Edge Cases

- What happens if `.wheel/state.json` is corrupted (invalid JSON)? Hooks should allow through and log a warning to stderr.
- What happens if the workflow file referenced in state.json no longer exists? `/wheel-status` should report the error; hooks should allow through.
- What happens if `.wheel/` directory doesn't exist? The file-existence check on `state.json` returns false, so hooks pass through.

## Requirements

### Functional Requirements

- **FR-001**: `/wheel-run <name>` skill MUST read `workflows/<name>.json`, validate the workflow (unique step IDs, required fields per step type, valid `context_from` references), create `.wheel/state.json` via `state_init()`, and output the first step instruction.
- **FR-002**: `/wheel-stop` skill MUST remove `.wheel/state.json`, archive it to `.wheel/history/<workflow-name>-<timestamp>.json`, and confirm deactivation. If no workflow is running, report that fact.
- **FR-003**: `/wheel-status` skill MUST read `.wheel/state.json` and display: workflow name, current step (index/total), step ID, step status, last command log entry, and elapsed time since `started_at`.
- **FR-004**: All hook scripts (`stop.sh`, `teammate-idle.sh`, `subagent-start.sh`, `subagent-stop.sh`, `session-start.sh`, `post-tool-use.sh`) MUST check `[[ ! -f ".wheel/state.json" ]]` as their first guard clause. If state.json does not exist, output `{"decision": "allow"}` (or just `exit 0` for post-tool-use) and exit immediately.
- **FR-005**: Remove the workflow auto-discovery logic from all hook scripts — the `find workflows/ -name '*.json'` pattern and `WHEEL_WORKFLOW` env var fallback (currently lines ~24-33 in stop.sh and equivalent in other hooks).
- **FR-006**: `/wheel-run` MUST validate the workflow JSON before creating state.json: check unique step IDs, required fields per step type, and valid `context_from` references using the existing `workflow_load()` function plus additional unique-ID validation.
- **FR-007**: `/wheel-run` MUST refuse to start if `.wheel/state.json` already exists, displaying the current workflow name and suggesting `/wheel-stop` or `/wheel-status`.

### Key Entities

- **state.json** (`.wheel/state.json`): Runtime workflow state — created by `/wheel-run`, read by hooks and `/wheel-status`, removed by `/wheel-stop`. Schema defined by `state_init()` in `lib/state.sh`.
- **Workflow definition** (`workflows/<name>.json`): Declarative workflow file — read by `/wheel-run` for validation and initialization. Unchanged by this feature.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A Claude Code session in a wheel-installed project starts with zero hook interception when no `.wheel/state.json` exists.
- **SC-002**: `/wheel-run example` creates state.json and the workflow proceeds through all steps via hook injection (same as current behavior, just manually triggered).
- **SC-003**: `/wheel-stop` removes state.json and the next hook event passes through with no side effects.
- **SC-004**: `/wheel-status` accurately reports current step index, step ID, and elapsed time.
- **SC-005**: Hook guard clause check adds < 5ms latency (single `[[ -f ]]` test).
- **SC-006**: Existing workflow execution behavior is unchanged — only activation/deactivation is new.

## Assumptions

- Skills are placed in `plugin-wheel/skills/<skill-name>/SKILL.md` and auto-discovered by Claude Code's plugin system.
- The `workflow_load()` function in `lib/workflow.sh` already validates required fields and branch target references. `/wheel-run` reuses this plus adds unique-step-ID validation.
- Single workflow per session is sufficient for v1 (no concurrent workflows).
- The `.wheel/history/` directory is created on first archive by `/wheel-stop`.
- Hooks read state.json from the consumer project's working directory (`.wheel/state.json`), not from the plugin directory.
