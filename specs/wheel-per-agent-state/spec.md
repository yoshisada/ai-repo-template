# Feature Specification: Wheel Per-Agent State Files

**Feature Branch**: `build/wheel-per-agent-state-20260406`
**Created**: 2026-04-06
**Status**: Draft
**PRD**: `docs/features/2026-04-06-wheel-per-agent-state/PRD.md`

## User Scenarios & Testing

### User Story 1 - Concurrent Agent Workflows (Priority: P1)

As a pipeline operator, I want each agent in my pipeline to run its own wheel workflow so that a specifier agent, implementer agent, and QA agent can each follow different workflows concurrently without interference.

**Why this priority**: This is the core motivation for the feature. Without per-agent state, wheel is unusable in multi-agent pipelines.

**Independent Test**: Start two workflows from different agents in the same session, verify both run to completion without corrupting each other's state.

**Acceptance Scenarios**:

1. **Given** agent A starts workflow "build" and agent B starts workflow "test" in the same session, **When** both agents execute hook events, **Then** each agent reads and writes only its own state file (`state_{session_id}_{agent_id_A}.json` and `state_{session_id}_{agent_id_B}.json`).
2. **Given** agent A has an active workflow, **When** agent B starts a different workflow, **Then** agent A's state file is not modified or read by agent B's hooks.
3. **Given** the main orchestrator (empty agent_id) starts a workflow, **When** a subagent with a non-empty agent_id starts a workflow in the same session, **Then** both state files coexist: `state_{session_id}.json` and `state_{session_id}_{agent_id}.json`.

---

### User Story 2 - Two-Phase State Creation (Priority: P1)

As a developer, I want the state file to encode ownership in its filename so that guard logic is implicit and no JSON field comparison is needed.

**Why this priority**: The two-phase creation pattern is the mechanism that makes concurrent workflows work. Without it, the skill (which lacks agent_id) cannot create a properly-named state file.

**Independent Test**: Run `/wheel-run`, verify `state_{session_id}.json` is created. Trigger a hook event, verify the file is renamed to `state_{session_id}_{agent_id}.json`.

**Acceptance Scenarios**:

1. **Given** `/wheel-run` is invoked, **When** `state_init` is called with the session_id, **Then** the state file is created as `.wheel/state_{session_id}.json` with `owner_session_id` set and `owner_agent_id` empty.
2. **Given** `state_{session_id}.json` exists (no agent_id in filename), **When** the first hook fires with both session_id and a non-empty agent_id, **Then** the file is renamed to `state_{session_id}_{agent_id}.json`.
3. **Given** `state_{session_id}.json` exists, **When** the first hook fires with an empty agent_id (main orchestrator), **Then** the file is NOT renamed and remains as `state_{session_id}.json`.

---

### User Story 3 - Hook State Resolution (Priority: P1)

As a hook script, I need to construct my expected state filename from session_id and agent_id in the hook input so I only read my own state file.

**Why this priority**: Every hook invocation must resolve the correct state file. This is the mechanism that prevents cross-agent interference.

**Independent Test**: Fire a hook with a known session_id and agent_id, verify it constructs and uses the correct filename.

**Acceptance Scenarios**:

1. **Given** a hook receives input with session_id=S1 and agent_id=A1, **When** it resolves the state file, **Then** it checks for `state_S1_A1.json` first, then falls back to `state_S1.json`.
2. **Given** neither `state_S1_A1.json` nor `state_S1.json` exists, **When** the hook tries to resolve, **Then** it outputs `{"decision": "approve"}` and exits (pass-through).
3. **Given** the hook resolves to `state_S1_A1.json`, **When** it processes the event, **Then** it never reads or writes any other `state_*.json` file.

---

### User Story 4 - Status and Stop for Multiple Workflows (Priority: P2)

As a developer, I want `/wheel-status` to show all active workflows and `/wheel-stop` to target specific ones, so I can monitor and manage concurrent workflows.

**Why this priority**: Management commands are secondary to the core concurrency mechanism but essential for usability.

**Independent Test**: Start two workflows, run `/wheel-status` and verify both are listed. Run `/wheel-stop` with a target identifier and verify only that workflow is stopped.

**Acceptance Scenarios**:

1. **Given** two state files exist (`state_S1_A1.json` and `state_S1_A2.json`), **When** `/wheel-status` runs, **Then** it lists both workflows with their names, session IDs, and agent IDs.
2. **Given** two state files exist, **When** `/wheel-stop` is run with no arguments and only one exists, **Then** that single workflow is stopped and archived.
3. **Given** two state files exist, **When** `/wheel-stop` is run with a specific identifier (session_id or agent_id), **Then** only the matching workflow is stopped and archived.
4. **Given** one state file exists, **When** `/wheel-stop` is run with no arguments, **Then** it stops that workflow (backward-compatible behavior).

---

### Edge Cases

- What happens if two hooks from different agents both see `state_{session_id}.json` and try to rename simultaneously? The first `mv` succeeds (atomic POSIX guarantee), the second gets "file not found" and falls back to checking its own filename.
- What happens if session_id is not available in hook input? The hook passes through with `{"decision": "approve"}` — same as current behavior.
- What happens if an agent crashes mid-workflow? Its state file remains in `.wheel/`. `/wheel-stop` can clean it up, and `/wheel-status` will show it as stale.
- What happens when the main orchestrator (empty agent_id) and a subagent both start workflows? The orchestrator's file is `state_{session_id}.json` and the subagent's is `state_{session_id}_{agent_id}.json` — no collision.

## Requirements

### Functional Requirements

- **FR-001**: State files MUST be named `state_{session_id}.json` at creation (by the skill) and renamed to `state_{session_id}_{agent_id}.json` by the first hook event that has both identifiers. If `agent_id` is empty, the file remains `state_{session_id}.json`.
- **FR-002**: `/wheel-run` MUST pass the current `session_id` to `state_init`, which creates the file as `.wheel/state_{session_id}.json`. The skill does NOT set `agent_id`.
- **FR-003**: The first hook event after state creation MUST detect the un-renamed `state_{session_id}.json`, extract `agent_id` from hook input, and rename it to `state_{session_id}_{agent_id}.json`. If `agent_id` is empty, no rename occurs.
- **FR-004**: Every hook handler MUST construct its expected state filename from `session_id` and `agent_id` in the hook input JSON. It checks for `state_{session_id}_{agent_id}.json` first, then falls back to `state_{session_id}.json` (pre-rename). If neither exists, pass through with `{"decision": "approve"}`.
- **FR-005**: Guard logic is replaced by filename-based ownership. If the hook's constructed state file exists, the hook is the owner and proceeds. No JSON field comparison needed.
- **FR-006**: Multiple `state_*.json` files MAY exist simultaneously in `.wheel/`. Each hook invocation MUST only read and write its own state file, never another agent's.
- **FR-007**: `/wheel-run` MUST check for an existing `state_{session_id}*.json` file for the current session before creating a new one. If found, block with an error.
- **FR-008**: `/wheel-status` MUST glob `state_*.json` in `.wheel/` and display all active workflows with their owner session/agent IDs.
- **FR-009**: `/wheel-stop` MUST accept an optional identifier to target a specific workflow. With no argument, it stops all workflows (or the only one if just one exists). It archives completed state files to `.wheel/history/` as before.
- **FR-010**: `engine_kickstart` MUST use the session_id-only filename (`state_{session_id}.json`) since it runs inside the skill before any hook fires.
- **FR-011**: `state_init` MUST accept `session_id` as a parameter and use it to construct the state filename. The `owner_session_id` field in the JSON is set at creation; `owner_agent_id` is set empty and populated on first hook rename.

### Key Entities

- **State File**: A JSON file in `.wheel/` named `state_{session_id}.json` or `state_{session_id}_{agent_id}.json` containing workflow execution state.
- **Session ID**: A string identifying the Claude Code session, available in hook input JSON.
- **Agent ID**: A string identifying the specific agent within a session, available in hook input JSON. Empty for the main orchestrator.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Two or more agents can each run independent workflows concurrently with zero state corruption.
- **SC-002**: `/wheel-status` correctly lists all active workflows across agents.
- **SC-003**: `/wheel-stop` can stop any individual workflow or all workflows.
- **SC-004**: Hook latency increase is imperceptible (<10ms over current guard).
- **SC-005**: All existing single-agent workflow patterns continue to work unchanged.

## Assumptions

- Claude Code hook input JSON contains `session_id` at the top level (confirmed working in session-guard feature).
- Claude Code hook input JSON contains `agent_id` at the top level for subagents (empty string for main orchestrator).
- `session_id` is accessible to skills via some mechanism (environment variable or conversation context).
- `mv` (rename) is atomic on the target filesystem (standard POSIX guarantee).
- No changes needed to dispatch.sh, workflow.sh, context.sh, or lock.sh — they already receive state_file path as a parameter.
