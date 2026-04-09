# Feature Specification: Wheel Team Primitives

**Feature Branch**: `build/wheel-team-primitives-20260409`  
**Created**: 2026-04-09  
**Status**: Draft  
**Input**: User description: "Wheel team primitives — 4 new step types for parallel agent execution in wheel workflows."

## User Scenarios & Testing

### User Story 1 - Static Fan-Out Execution (Priority: P1)

As a workflow author, I want to define multiple teammate steps in my workflow JSON that each run the same sub-workflow with different assigned work, so I can parallelize a known workload without writing orchestration code.

**Why this priority**: This is the core value proposition — enabling parallel execution of independent work items. Without this, every workflow runs sequentially regardless of workload.

**Independent Test**: Can be tested by creating a workflow with team-create, 3 teammate steps, team-wait, and team-delete. Each teammate runs a sub-workflow with different data. Verify all 3 run in parallel and their outputs are collected.

**Acceptance Scenarios**:

1. **Given** a workflow JSON with a `team-create` step, 3 `teammate` steps referencing the same sub-workflow but different assignments, a `team-wait` step, and a `team-delete` step, **When** the workflow is executed, **Then** all 3 teammates are spawned, run their sub-workflows, and the wait step collects all outputs before the workflow proceeds.
2. **Given** a `team-create` step with no explicit team name, **When** the step executes, **Then** a team name is auto-generated from the workflow name and step ID.
3. **Given** a `team-create` step is run twice with the same team name, **When** the second execution occurs, **Then** it is a no-op and does not error.

---

### User Story 2 - Dynamic Fan-Out from Previous Step Output (Priority: P1)

As a workflow author, I want to define a single teammate step with `loop_from` that reads a previous step's JSON array output and spawns one teammate per entry, so the parallelism scales dynamically with the workload size.

**Why this priority**: Many real workloads have a variable number of items (pages, components, modules). Dynamic spawning eliminates the need to hard-code teammate counts.

**Independent Test**: Can be tested by creating a workflow where step 1 outputs a JSON array of 5 items, and a teammate step with `loop_from` referencing step 1 spawns 5 agents. Verify correct count and each agent receives its assigned item.

**Acceptance Scenarios**:

1. **Given** a teammate step with `loop_from` referencing a step whose output is a JSON array of 5 items, **When** the step executes, **Then** 5 teammate agents are spawned, each receiving its array entry as the assignment.
2. **Given** a teammate step with `loop_from` and `max_agents: 3` referencing a step with 9 items, **When** the step executes, **Then** 3 agents are spawned, each receiving 3 items distributed round-robin.
3. **Given** a teammate step with `loop_from` and no `max_agents`, **When** the step executes with 10 items, **Then** at most 5 agents are spawned (default cap), with items distributed across them.

---

### User Story 3 - Wait and Collect Results (Priority: P1)

As a workflow author, I want a step that blocks until all teammates finish and collects their outputs, so downstream steps can aggregate or process the combined results.

**Why this priority**: Without a synchronization point, the workflow cannot use teammate outputs. This is essential for fan-in after fan-out.

**Independent Test**: Can be tested by running a team with 3 teammates of varying duration. Verify the wait step blocks until all complete and writes a summary with per-teammate status.

**Acceptance Scenarios**:

1. **Given** a `team-wait` step referencing a team with 3 active teammates, **When** all 3 complete, **Then** the wait step writes a summary containing total count, completed count, per-teammate status, and output paths.
2. **Given** a `team-wait` step with `collect_to` set, **When** teammates complete, **Then** each teammate's output directory is copied to the collect path.
3. **Given** a team where 2 of 3 teammates succeed and 1 fails, **When** the `team-wait` step completes, **Then** it reports partial results (2 completed, 1 failed) and does NOT fail the workflow.

---

### User Story 4 - Failure Resilience (Priority: P2)

As a workflow author, I want the pipeline to continue even if some teammates fail, collecting partial results and reporting which teammates succeeded and which failed, so one bad item does not block the entire workflow.

**Why this priority**: Production workloads must be robust. Partial success is better than total failure when processing independent items.

**Independent Test**: Can be tested by spawning 3 teammates where 1 is designed to fail. Verify the wait step reports partial results and the workflow continues.

**Acceptance Scenarios**:

1. **Given** a team with 3 teammates where 1 fails during execution, **When** the `team-wait` step completes, **Then** it reports 2 completed, 1 failed with status details, and the workflow advances.
2. **Given** a downstream step after `team-wait`, **When** it reads the wait step's output, **Then** it can distinguish successful from failed teammates and act accordingly.

---

### User Story 5 - Team Cleanup and Cascade Stop (Priority: P2)

As a workflow author, I want a step that gracefully shuts down all agents on a team and cleans up resources. If the parent workflow is stopped, all active teammates must be stopped too.

**Why this priority**: Resource cleanup prevents orphaned agents and stale state. Cascade stop is essential for workflow cancellation.

**Independent Test**: Can be tested by running a team, then executing team-delete. Verify all agents are shut down and team resources are removed. Separately, test stopping a parent workflow while teammates are active and verify cascade cleanup.

**Acceptance Scenarios**:

1. **Given** a `team-delete` step referencing a team with completed teammates, **When** it executes, **Then** all agents are shut down and team resources are cleaned up.
2. **Given** a `team-delete` step reached while some teammates are still running, **When** it executes, **Then** remaining agents are force-terminated before cleanup.
3. **Given** a running parent workflow with active teammates, **When** the user stops the workflow via `/wheel-stop`, **Then** all active teammates are stopped and their teams are cleaned up as part of the cascade.
4. **Given** a `team-delete` step is called on an already-deleted team, **When** it executes, **Then** it is a no-op and does not error.

---

### User Story 6 - Sub-Workflow Context Passing (Priority: P2)

As a workflow author, I want teammates to receive context from earlier workflow steps and their specific work assignment, so each teammate has the information it needs to execute its sub-workflow.

**Why this priority**: Context passing bridges the gap between the parent workflow's state and each teammate's independent execution. Without it, teammates would run blind.

**Independent Test**: Can be tested by creating a workflow where step 1 produces output, and a teammate step references it via `context_from`. Verify the teammate receives the context and assignment as readable files.

**Acceptance Scenarios**:

1. **Given** a teammate step with `context_from: ["step-1"]` and `assign: {"page": 3}`, **When** the teammate is spawned, **Then** it finds `context.json` (containing step-1's output) and `assignment.json` (containing `{"page": 3}`) in its output directory.
2. **Given** a sub-workflow running as a teammate, **When** it references `_context` or `_assignment` as step IDs in `context_from`, **Then** it receives the parent-provided context and assignment data.

---

### User Story 7 - Sub-Workflow Reuse (Priority: P3)

As a workflow author, I want teammates to run existing workflow JSON files as sub-workflows, so I can reuse workflow definitions across different team configurations without duplication.

**Why this priority**: Reusability reduces maintenance burden and ensures consistency. The same sub-workflow can be used in static and dynamic fan-out scenarios.

**Independent Test**: Can be tested by creating a reusable sub-workflow JSON and referencing it from multiple teammate steps in different parent workflows.

**Acceptance Scenarios**:

1. **Given** a teammate step with `workflow: "build-page"`, **When** the teammate is spawned, **Then** it resolves and executes the `build-page` workflow JSON using the same resolution rules as `"type": "workflow"` steps.

---

### Edge Cases

- What happens when `loop_from` references a step whose output is not valid JSON or not an array?
- What happens when `loop_from` produces an empty array (0 items)?
- What happens when `max_agents` is set to 0 or a negative number?
- What happens when a teammate's sub-workflow creates its own state file — does it interfere with the parent workflow's state?
- What happens when two team-create steps use the same team name in the same workflow?
- What happens when team-wait is reached but no teammates were spawned (e.g., empty loop_from)?
- What happens when a teammate tries to spawn a nested sub-team (not supported in v1)?

## Requirements

### Functional Requirements

**Step Type: team-create**

- **FR-001**: System MUST provide a `team-create` step type that creates a Claude Code agent team and stores the team name in workflow state for reference by subsequent steps.
- **FR-002**: The `team-create` step MUST accept an optional `team_name` field. If omitted, the system generates a name from the workflow name and step ID: `{workflow-name}-{step-id}`.
- **FR-003**: The `team-create` step MUST be idempotent — creating a team that already exists is a no-op, not an error.
- **FR-004**: The workflow state MUST record the team name under `teams.{step-id}` so that teammate, team-wait, and team-delete steps can reference it.

**Step Type: teammate**

- **FR-005**: System MUST provide a `teammate` step type that spawns a single agent joining the referenced team and running a sub-workflow.
- **FR-006**: The `teammate` step MUST accept: `team` (required, references team-create step ID), `workflow` (required, sub-workflow to run), `context_from` (optional, array of step IDs for context), `assign` (optional, JSON payload for work assignment), and `name` (optional, human-readable agent name).
- **FR-007**: The `teammate` step MUST create a task entry for the spawned agent so the team-wait step can track completion.
- **FR-008**: The `teammate` step MUST spawn the agent in the background. The parent workflow advances immediately after spawning — it does not wait for the teammate to finish.
- **FR-009**: The spawned agent MUST receive: the sub-workflow to execute, context from referenced steps, the assignment payload, instructions to mark its task complete when done, and instructions to write output to a predictable location.
- **FR-010**: The spawned agent MUST run with permissions that avoid blocking on prompts during automated execution.

**Dynamic Spawning: loop_from**

- **FR-011**: The `teammate` step MUST accept an optional `loop_from` field — the ID of a previous step whose output is a JSON array.
- **FR-012**: When `loop_from` is present, the system MUST read the referenced step's output, parse it as a JSON array, and spawn one teammate per array entry, each receiving its entry as the assignment.
- **FR-013**: When `loop_from` is present, a `max_agents` field (optional, default 5) MUST cap the number of agents. Excess entries are distributed across agents in round-robin groups.
- **FR-014**: Each dynamically spawned agent MUST receive a unique name: `{step-id}-{index}`.

**Step Type: team-wait**

- **FR-015**: System MUST provide a `team-wait` step type that blocks the parent workflow until all teammates on the referenced team have completed or failed.
- **FR-016**: The `team-wait` step MUST accept: `team` (required, references team-create step ID) and `collect_to` (optional, directory path for collected outputs).
- **FR-017**: The system MUST poll teammate completion status at 30-second intervals.
- **FR-018**: When all teammates are done, the `team-wait` step MUST write a summary containing: total count, completed count, failed count, per-teammate status with name/status/output-path/duration, and if `collect_to` is set, copy outputs to the collect path.
- **FR-019**: The `team-wait` step MUST NOT fail if some teammates failed. It reports partial results and advances the workflow.

**Step Type: team-delete**

- **FR-020**: System MUST provide a `team-delete` step type that gracefully shuts down all agents on a team and cleans up resources.
- **FR-021**: The `team-delete` step MUST send shutdown requests to all teammates, wait for confirmation, then remove the team and associated resources.
- **FR-022**: The `team-delete` step MUST accept a `team` field (required, references team-create step ID).
- **FR-023**: If teammates are still running when `team-delete` is reached, the step MUST force-terminate remaining agents before cleanup.

**Engine Integration**

- **FR-024**: The wheel engine MUST recognize all four new step types and handle them in the PostToolUse hook alongside existing step types (command, agent, workflow, branch).
- **FR-025**: Team-related state (team name, teammate task IDs, statuses) MUST be stored in the workflow state file under a `teams` key, following the existing state file format.
- **FR-026**: The `team-wait` step MUST be implemented in the PostToolUse hook as a polling mechanism that checks teammate status on each invocation and only advances the cursor when all teammates are done.
- **FR-027**: Teammate sub-workflows MUST run with their own independent state files. The parent workflow's state file tracks the team, not individual sub-workflow progress.
- **FR-028**: If the parent workflow is stopped, all active teammates MUST be stopped and their teams cleaned up as part of cascade stop logic.

**Sub-Workflow Context Passing**

- **FR-029**: Context from `context_from` steps MUST be passed to the teammate by writing a combined context file containing the referenced step outputs.
- **FR-030**: The `assign` payload MUST be written to a file so the sub-workflow can read it in its first step.
- **FR-031**: The sub-workflow's agent steps MUST be able to reference context and assignment data as if they were outputs from previous steps (via synthetic step IDs `_context` and `_assignment`).

### Key Entities

- **Team**: A named group of parallel agents created by `team-create` and destroyed by `team-delete`. Tracked in workflow state under `teams.{step-id}`.
- **Teammate**: A single agent within a team, running an independent sub-workflow. Has a unique name, a task entry for tracking, and an output directory.
- **Assignment**: A JSON payload describing the specific work a teammate is responsible for. Passed via `assign` (static) or `loop_from` (dynamic).
- **Sub-Workflow**: An existing workflow JSON file executed by a teammate agent. Runs with its own independent state file.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A workflow with team-create, 3 static teammates, team-wait, and team-delete successfully spawns 3 agents, waits for all to finish, and collects outputs — entirely via the hook-driven engine.
- **SC-002**: A workflow with `loop_from` dynamically spawns the correct number of agents based on a previous step's JSON array output (verified with arrays of 1, 5, and 15 items).
- **SC-003**: When some teammates fail, `team-wait` collects partial results and the workflow continues without error.
- **SC-004**: Stopping a parent workflow with active teammates cascades the stop to all teammates within the same engine cycle.
- **SC-005**: Existing workflow types (command, agent, workflow, branch) continue to work unchanged after the new step types are added.
- **SC-006**: The teammate spawn step completes in under 5 seconds (it only triggers the spawn, does not wait).
- **SC-007**: Team state in the workflow state file remains under 10KB even with 10 active teammates.
- **SC-008**: All team operations are idempotent — re-running team-create on an existing team or team-delete on a deleted team produces no error.

## Assumptions

- The Claude Code agent teams API (TeamCreate, TaskCreate, TaskList, TaskUpdate, TeamDelete, Agent, SendMessage) is available and functional in the execution environment.
- Teammate sub-workflows run in the same working directory as the parent workflow.
- The existing wheel engine's PostToolUse hook system can handle the new step types without architectural changes — only new handler branches are needed.
- The existing per-agent state resolution (guard.sh with owner_session_id/owner_agent_id) correctly isolates teammate state files from the parent workflow's state file.
- Nested teams (a teammate spawning its own sub-team) are explicitly out of scope for this version.
- The `team-wait` polling relies on the PostToolUse hook firing periodically; if no tool calls are happening, the wait step cannot advance until the next tool call occurs.
- Sub-workflow resolution follows the same rules as existing `"type": "workflow"` steps (local `workflows/` directory or `plugin:name` prefix).
