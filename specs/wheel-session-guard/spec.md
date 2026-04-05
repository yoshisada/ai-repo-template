# Feature Specification: Wheel Session Guard

**Feature Branch**: `build/wheel-session-guard-20260405`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "Implement wheel session guard — add ownership tracking to .wheel/state.json so only the originating agent can advance a workflow."

## User Scenarios & Testing

### User Story 1 - Workflow Isolation in Multi-Agent Pipelines (Priority: P1)

As a pipeline operator, I start a wheel workflow inside a `/build-prd` pipeline. The pipeline spawns subagents (QA, auditor, implementer) that generate hook events. Only the agent that started the workflow should advance the state machine — all other agents' hook events should pass through without touching workflow state.

**Why this priority**: This is the core problem. Without isolation, wheel workflows are unsafe in any multi-agent context, which is the primary use case for structured pipeline steps.

**Independent Test**: Start a workflow as agent X, then simulate hook events from agent Y. Verify agent Y's events produce approve/pass-through responses and do not modify state.json.

**Acceptance Scenarios**:

1. **Given** a running workflow owned by agent X, **When** agent Y triggers a stop hook event, **Then** the hook returns `{"decision": "approve"}` without modifying state.json
2. **Given** a running workflow owned by agent X, **When** agent X triggers a stop hook event, **Then** the hook processes the event normally and may advance the workflow
3. **Given** a running workflow owned by agent X, **When** agent Y triggers a post-tool-use hook event, **Then** the hook returns `{"hookEventName": "PostToolUse"}` without logging commands or advancing state

---

### User Story 2 - Ownership Stamping at Workflow Start (Priority: P1)

As a developer, I start a workflow via `/wheel-run`. Since the skill does not receive hook input (no session_id/agent_id available), the first hook event after state creation must stamp the ownership fields into state.json. This ensures the workflow is owned by the agent that initiated it.

**Why this priority**: Without ownership stamping, the guard has nothing to compare against — this is a prerequisite for Story 1.

**Independent Test**: Run `/wheel-run`, then trigger the first hook event. Verify state.json now contains `owner_session_id` and `owner_agent_id` fields matching the hook event's session/agent context.

**Acceptance Scenarios**:

1. **Given** a newly created state.json without ownership fields, **When** the first hook event fires from the originating agent, **Then** `owner_session_id` and `owner_agent_id` are written to state.json
2. **Given** a state.json that already has ownership fields set, **When** a subsequent hook event fires, **Then** the ownership fields are NOT overwritten

---

### User Story 3 - Status and Stop Work from Any Session (Priority: P2)

As a developer, I want to check workflow status or stop a workflow from any session or agent, even if I'm not the owner. This ensures operability — a user can always kill a stuck or runaway workflow regardless of which agent started it.

**Why this priority**: Important for operability but secondary to the core isolation mechanism.

**Independent Test**: Start a workflow as agent X, then run `/wheel-status` and `/wheel-stop` from a different session. Verify both commands work without being blocked by the guard.

**Acceptance Scenarios**:

1. **Given** a running workflow owned by agent X, **When** any agent runs `/wheel-status`, **Then** the status is displayed correctly
2. **Given** a running workflow owned by agent X, **When** any agent runs `/wheel-stop`, **Then** the workflow is stopped and state is archived

---

### User Story 4 - Shared Guard Function (Priority: P2)

As a maintainer, I want the session guard logic to live in a single shared library file (`lib/guard.sh`) rather than being duplicated across all 6 hook scripts. This reduces maintenance burden and ensures consistent behavior.

**Why this priority**: Important for code quality but the guard mechanism itself takes precedence.

**Independent Test**: Verify that all 6 hook scripts source `lib/guard.sh` and call the shared guard function, and that the guard function is defined in exactly one file.

**Acceptance Scenarios**:

1. **Given** the guard function is defined in `lib/guard.sh`, **When** any hook script sources it and calls the guard, **Then** the guard correctly compares session/agent IDs and returns pass-through or allows processing

---

### Edge Cases

- What happens when a workflow is started and the first hook event comes from a different agent than the one that ran `/wheel-run`? The ownership fields get stamped with the wrong agent, but since `/wheel-run` creates state.json, the first hook from the same agent should fire next. If a race occurs, `/wheel-stop` is always available as a fallback.
- What happens when `session_id` is missing from hook input? The guard should treat missing session_id as a non-match and return pass-through (approve). This prevents unidentifiable events from modifying state.
- What happens when `agent_id` is absent from hook input (e.g., the main orchestrator, not a subagent)? If `owner_agent_id` is also empty/null, match on `session_id` alone. If `owner_agent_id` is set but hook input has no `agent_id`, treat as non-match.
- What happens if the user disconnects and reconnects (new session_id)? The workflow becomes orphaned — ownership won't match. The user can always run `/wheel-stop` (exempt from guard) to clean up and restart.

## Requirements

### Functional Requirements

- **FR-001**: `state_init` MUST capture `session_id` and `agent_id` (if present) from the calling context and store them in `.wheel/state.json` as `owner_session_id` and `owner_agent_id`. Since `/wheel-run` is a skill without hook input, these fields are initialized as empty strings to be stamped by the first hook event.
- **FR-002**: Every hook handler (stop.sh, post-tool-use.sh, subagent-start.sh, subagent-stop.sh, teammate-idle.sh, session-start.sh) MUST call a shared guard function before processing. The guard reads `session_id` and `agent_id` from the hook input JSON and compares against the owner fields in state.json.
- **FR-003**: The guard MUST match on `session_id` first. If `owner_agent_id` is also set (non-empty), it MUST additionally match `agent_id`. Events from the same session but a different agent MUST be allowed to pass through (approve) without touching state.
- **FR-004**: The first hook event after state creation MUST stamp the `owner_session_id` and `owner_agent_id` fields if they are currently empty. Subsequent hook events MUST NOT overwrite these fields.
- **FR-005**: `/wheel-status` and `/wheel-stop` MUST work regardless of ownership — any agent can check status or stop a workflow. The guard is not applied to these skill commands.
- **FR-006**: The guard logic MUST live in a shared `lib/guard.sh` file to avoid duplicating the comparison logic across 6 hook scripts.
- **FR-007**: If the hook input lacks a `session_id` field, the guard MUST return pass-through (approve/no-op) without modifying state. Unidentifiable events are never allowed to advance a workflow.

### Key Entities

- **Owner Context**: The `owner_session_id` and `owner_agent_id` fields in state.json that identify which agent owns the running workflow
- **Hook Input Context**: The `session_id` and `agent_id` fields extracted from the JSON hook input that identify who triggered the current event
- **Guard Function**: The shared function in `lib/guard.sh` that compares owner context against hook input context and decides whether to allow or pass-through

## Success Criteria

### Measurable Outcomes

- **SC-001**: A workflow started by one agent is never advanced or modified by hook events from a different agent in the same session
- **SC-002**: A workflow started in one session is never advanced or modified by hook events from a different session
- **SC-003**: Any agent from any session can successfully check status or stop a workflow
- **SC-004**: Guard check adds less than 10ms per hook invocation (a single `jq` read + compare)
- **SC-005**: All 6 hook scripts use the shared guard function from `lib/guard.sh` with zero duplicated guard logic

## Assumptions

- Hook input JSON always contains a `session_id` field when the event comes from an identifiable agent (Claude Code provides this)
- The `agent_id` field is present in hook input only when the event originates from a subagent or teammate (not the main orchestrator)
- `/wheel-status` and `/wheel-stop` are implemented as skills (not hooks), so they don't pass through the hook guard
- Existing state.json schema can be extended with new top-level fields without breaking existing functionality
- The first hook event after `/wheel-run` will reliably come from the same agent that ran the skill, due to synchronous event dispatch
