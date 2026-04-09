# Research: Wheel Team Primitives

## Decision 1: Handler Architecture — Instruction Injection vs. Direct Tool Calls

**Decision**: Use instruction injection (same pattern as existing `dispatch_agent`) for team-create, teammate, and team-delete. The hook blocks the orchestrator with an instruction message, and the LLM executes the required Claude Code tool calls (TeamCreate, Agent, TeamDelete).

**Rationale**: Wheel hooks cannot directly invoke Claude Code tools (TeamCreate, Agent, etc.) — they are LLM tools, not CLI commands. The existing dispatch pattern already solves this: the hook returns `{"decision": "block", "reason": "<instruction>"}` which injects the instruction into the orchestrator's context. The orchestrator then executes the tool call, and the PostToolUse hook detects completion and advances the cursor.

**Alternatives considered**:
- Direct bash invocation of team API: Not possible — TeamCreate/Agent/TeamDelete are Claude Code LLM tools, not CLI commands.
- New hook type for team operations: Unnecessary complexity — the existing stop/post_tool_use pattern handles this.

## Decision 2: team-wait Polling Mechanism

**Decision**: Implement team-wait as a blocking step that checks TaskList on each stop hook invocation. The step stays in "working" status until all teammate tasks are complete. Each time the stop hook fires (naturally, whenever the orchestrator tries to stop), the handler checks teammate status.

**Rationale**: The PRD identifies a risk that hooks only fire on tool use. However, the Stop hook fires every time the orchestrator completes a turn and tries to stop — which happens naturally as the LLM processes. The 30-second interval noted in the PRD is a target for how often status should be checked, but in practice the hook fires more frequently. To avoid excessive polling, the handler can track the last check time and skip if < 30 seconds elapsed.

**Alternatives considered**:
- Timer-based mechanism: Would require a background process or cron, adding complexity outside the hook model.
- Busy-wait in bash: Would block the hook process and prevent other operations. Rejected.
- Periodic command step: Would require the LLM to execute a polling command, adding unnecessary token cost.

## Decision 3: Teammate State Isolation

**Decision**: Teammate sub-workflows create their own state files (`.wheel/state_{agent-id}.json`). The parent workflow's state file tracks only the team metadata (team name, teammate task IDs, statuses) under a `teams` key. Teammate state files use the teammate's agent_id as the owner, ensuring guard.sh correctly routes hooks to the right state file.

**Rationale**: The existing guard.sh already resolves state files by matching `owner_session_id` and `owner_agent_id` in the state JSON against the hook input. Teammates spawned via the Agent tool get their own agent_id, so their hooks automatically route to their own state files. No changes to guard.sh are needed.

**Alternatives considered**:
- Shared state file with section per teammate: Would cause contention and violate the existing one-state-per-agent model. Rejected.
- No state file for teammates (track only via TaskList): Would lose wheel's step-level progress tracking for sub-workflows. Rejected.

## Decision 4: Context and Assignment File Location

**Decision**: Write `context.json` and `assignment.json` to `.wheel/outputs/team-{team-name}/{agent-name}/` before spawning each teammate. Sub-workflows reference these via synthetic step IDs `_context` and `_assignment` in `context_from`.

**Rationale**: The existing output directory convention (`.wheel/outputs/`) is already established. Placing team outputs in a subdirectory organized by team name and agent name keeps them predictable and glob-friendly (NFR-005). The synthetic step ID approach integrates cleanly with context.sh's existing `context_build()` function — just add a check for `_context` and `_assignment` IDs that reads from the known file paths instead of looking up state step outputs.

**Alternatives considered**:
- Pass context inline in the agent prompt: Would duplicate data and bloat prompts for large contexts. Rejected.
- Use environment variables: Not supported across agent boundaries in Claude Code. Rejected.

## Decision 5: Step Type as Hook-Driven vs. Inline-Executable

**Decision**: 
- `team-create`: Instruction injection (agent must call TeamCreate tool)
- `teammate`: Instruction injection (agent must call Agent tool)  
- `team-wait`: Polling in stop hook (blocks until all done)
- `team-delete`: Instruction injection (agent must call TeamDelete tool)

**Rationale**: team-create, teammate, and team-delete require Claude Code tool calls that only the LLM can execute. team-wait is purely a status check that the hook can perform via TaskList (also an LLM tool, but the hook can instruct the agent to call it and check the result). However, since TaskList is also an LLM tool, team-wait will also use instruction injection — telling the agent to call TaskList and write results. The hook then detects when the status file shows all teammates complete.

**Revised decision**: All four types use instruction injection. team-wait instructs the agent to periodically check TaskList and report status. The PostToolUse hook detects when the agent writes a completion marker and advances the cursor.
