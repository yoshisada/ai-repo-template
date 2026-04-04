# Feature Specification: Wheel — Hook-based Workflow Engine Plugin

**Feature Branch**: `build/wheel-20260403`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: PRD at `docs/features/2026-04-03-wheel/PRD.md`

## User Scenarios & Testing

### User Story 1 - Define and Run a Linear Workflow (Priority: P1)

As a plugin developer, I want to define a multi-step workflow as a JSON file and have the engine execute steps in order — each agent receives only its step instruction via hooks, with no LLM routing decisions.

**Why this priority**: This is the core value proposition. Without linear step execution, nothing else works.

**Independent Test**: Define a 3-step workflow JSON, start a session, and verify that state.json advances through steps 1→2→3 with each step's instruction injected via the Stop hook.

**Acceptance Scenarios**:

1. **Given** a workflow.json with 3 linear agent steps, **When** the engine starts, **Then** the Stop hook injects step 1's instruction and state.json shows step 1 as `working`
2. **Given** step 1 completes (SubagentStop fires), **When** the engine processes the event, **Then** state.json advances to step 2 and the next Stop hook injects step 2's instruction
3. **Given** all steps complete, **When** the final SubagentStop fires, **Then** state.json shows all steps as `done` and the Stop hook allows the session to end
4. **Given** a workflow with `type: command` steps, **When** the engine reaches a command step, **Then** it executes the shell command directly in the hook, records output/exit_code/timestamp in state.json, and advances without LLM involvement

---

### User Story 2 - Resume a Crashed Pipeline (Priority: P1)

As a developer, I want a crashed or interrupted session to resume from the last completed step, so I don't lose progress on long-running pipelines.

**Why this priority**: Resumability is a primary differentiator over the current LLM-as-router approach. Without it, crashes still mean full restarts.

**Independent Test**: Run a 3-step workflow, kill the session after step 1 completes, restart the session, and verify it resumes at step 2.

**Acceptance Scenarios**:

1. **Given** state.json shows steps 1-2 as `done` and step 3 as `pending`, **When** a new session starts with `resume` event, **Then** the SessionStart hook reads state.json and resumes execution at step 3
2. **Given** state.json shows step 2 as `working` (partially complete), **When** a session resumes, **Then** the engine re-runs step 2 from the beginning with its command log available for context

---

### User Story 3 - Parallel Agent Fan-out/Fan-in (Priority: P2)

As a plugin developer, I want a single workflow step to spawn multiple agents that run in parallel, with deterministic detection of when all agents finish before advancing.

**Why this priority**: Parallel execution is critical for real pipelines (e.g., multiple implementers), but the core linear engine must work first.

**Independent Test**: Define a workflow with a parallel step containing 3 agents, run it, and verify all 3 agents receive instructions and the engine advances only after all 3 complete.

**Acceptance Scenarios**:

1. **Given** a step with `type: parallel` and 3 agent assignments, **When** the step becomes active, **Then** TeammateIdle injects each agent's specific instruction and state.json tracks each agent individually
2. **Given** 2 of 3 parallel agents complete, **When** SubagentStop fires for agent 2, **Then** state.json shows 2 `done` and 1 `working`, and the step does NOT advance
3. **Given** all 3 parallel agents complete, **When** the final SubagentStop fires, **Then** mkdir-based atomic locking detects fan-in completion and advances to the next step

---

### User Story 4 - Approval Gates (Priority: P2)

As a developer, I want approval gates in my workflow so I can review artifacts before the pipeline proceeds to the next step.

**Why this priority**: Human-in-the-loop checkpoints are important for production pipelines but not needed for the MVP engine to function.

**Independent Test**: Define a workflow with an approval step, run it, and verify the pipeline blocks until explicit approval is given.

**Acceptance Scenarios**:

1. **Given** a step with `type: approval`, **When** the step becomes active, **Then** the engine blocks execution and displays a message to the user
2. **Given** an active approval gate, **When** the user approves via TeammateIdle, **Then** the engine advances to the next step and records the approval in state.json

---

### User Story 5 - Branch and Loop Control Flow (Priority: P2)

As a pipeline author, I want branch and loop steps so workflows can react to command results and retry failures without LLM involvement.

**Why this priority**: Control flow makes workflows practical for real-world pipelines with conditional logic and retry patterns.

**Independent Test**: Define a workflow with a branch step that checks a condition, verify it jumps to the correct target. Define a loop step, verify it retries until the condition is met or max iterations is reached.

**Acceptance Scenarios**:

1. **Given** a `type: branch` step with a condition `test -f output.json`, **When** the file exists, **Then** the engine jumps to the `if_zero` target step ID
2. **Given** a `type: branch` step, **When** the condition fails (non-zero exit), **Then** the engine jumps to the `if_nonzero` target step ID
3. **Given** a `type: loop` step with `max_iterations: 3` and a failing condition, **When** the loop exhausts iterations, **Then** the engine either fails the workflow or continues based on the `on_exhaustion` setting
4. **Given** a `type: loop` step with a condition that succeeds on iteration 2, **When** the condition succeeds, **Then** the loop exits and the engine advances to the next step

---

### User Story 6 - Command Audit Trail (Priority: P3)

As a pipeline author, I want a full audit log of every command the LLM executes during agent steps, so I can debug and audit pipeline behavior.

**Why this priority**: Audit trail is valuable for debugging and compliance but not required for basic engine operation.

**Independent Test**: Run a workflow with an agent step, have the agent execute bash commands, and verify each command appears in state.json's command_log with command text, exit code, and timestamp.

**Acceptance Scenarios**:

1. **Given** an agent step is active, **When** the agent runs a Bash command, **Then** the PostToolUse(Bash) hook appends `{command, exit_code, timestamp}` to the step's `command_log` in state.json
2. **Given** a resumed session with a partially-complete agent step, **When** the session resumes, **Then** the command log from the previous run is available for context injection

---

### User Story 7 - Plugin Packaging and Distribution (Priority: P3)

As a plugin developer, I want Wheel published as `@yoshisada/wheel` on npm with a scaffold script, so consumer projects can install and use it easily.

**Why this priority**: Distribution is necessary for adoption but can be done after the engine is proven.

**Independent Test**: Run `npx @yoshisada/wheel init` in an empty project and verify it scaffolds the expected directory structure and hook configuration.

**Acceptance Scenarios**:

1. **Given** a consumer project without Wheel, **When** `npx @yoshisada/wheel init` runs, **Then** it creates `.wheel/`, `workflows/`, and configures hooks in `.claude/settings.json`
2. **Given** the plugin is installed, **When** a workflow.json exists in `workflows/`, **Then** the hooks activate and the engine can run the workflow

---

### Edge Cases

- What happens when state.json is corrupted or missing mid-workflow? Engine should detect and report, not crash silently.
- What happens when two SubagentStop hooks fire simultaneously for the same parallel step? mkdir-based locking must prevent double-advance.
- What happens when a command step produces output larger than reasonable for state.json? Truncate or store externally.
- What happens when a workflow.json references a non-existent step ID in a branch target? Fail with a clear error at workflow load time, not at runtime.
- What happens when jq is not installed? Detect and report the missing dependency at startup.

## Requirements

### Functional Requirements

**Core Engine**

- **FR-001**: Engine (`engine.sh`) MUST read a workflow definition and `state.json`, determine the current step, and provide the next instruction to execute
- **FR-002**: Engine MUST persist workflow state to `.wheel/state.json`, including current step index, step statuses, agent statuses, and step outputs
- **FR-003**: Engine MUST support linear step sequencing — advance a step cursor through an ordered list of steps, injecting the next instruction via the Stop hook

**Hook Integration**

- **FR-004**: System MUST implement a `Stop` hook handler that gates the parent orchestrator, injects the next step instruction, or allows stop when the workflow is complete
- **FR-005**: System MUST implement a `TeammateIdle` hook handler that gates agents with their agent-specific next task, or allows idle when the step is done
- **FR-006**: System MUST implement a `SubagentStart` hook handler that injects previous step output as `additionalContext` into newly spawned agents
- **FR-007**: System MUST implement a `SubagentStop` hook handler that marks agents done in state.json, checks if all parallel agents for the current step have finished, and advances to the next step if so
- **FR-008**: System MUST implement a `SessionStart(resume)` hook handler that reloads state.json and resumes from the last completed step

**Parallel Execution**

- **FR-009**: System MUST support parallel agent fan-out — a single step can spawn multiple agents tracked individually by `agent_type` in state.json
- **FR-010**: System MUST support atomic fan-in — use `mkdir`-based locking to safely detect when all parallel agents for a step have completed, then advance
- **FR-011**: System MUST track per-agent state (`working`, `idle`, `done`, `failed`) within parallel steps

**Workflow Definition**

- **FR-012**: System MUST define a workflow definition format (JSON) that specifies: step ID, step type (linear/parallel/command/branch/loop/approval), agent assignments, context dependencies, and approval requirements
- **FR-013**: System MUST support approval gates — steps that block execution until explicit human approval

**Plugin Structure**

- **FR-014**: System MUST be packaged as a Claude Code plugin with proper `.claude-plugin/plugin.json` manifest
- **FR-015**: System MUST be publishable to npm as `@yoshisada/wheel`
- **FR-016**: System MUST provide a scaffold/init script (`bin/init.mjs`) for consumer projects

**Command Steps**

- **FR-019**: System MUST support `type: command` steps that execute shell commands directly in the hook script, capture output and exit code, and advance without LLM involvement
- **FR-020**: Consecutive command steps MUST chain — execute in a single hook invocation via `exec "$0"` without returning to the LLM between them
- **FR-021**: Command steps MUST record output, exit code, and timestamp in state.json for auditability

**Command Audit Trail**

- **FR-022**: System MUST implement a `PostToolUse(Bash)` hook handler that logs every command the LLM executes during agent steps into the current step's `command_log` array in state.json
- **FR-023**: On session resume, the command log MUST be available so the engine can determine what work was already done in a partially-completed agent step

**Control Flow**

- **FR-024**: System MUST support `type: branch` steps — evaluate a shell condition expression, jump to a target step ID based on exit code (`if_zero` / `if_nonzero`), with no LLM involvement
- **FR-025**: System MUST support `type: loop` steps — repeat a substep until a condition is met or `max_iterations` is reached, with configurable `on_exhaustion` behavior (`fail` or `continue`)
- **FR-026**: Loop substeps MUST support both `type: agent` and `type: command`, using the same dispatch logic as top-level steps

**Context Management**

- **FR-027**: System MUST support per-step context injection — each agent receives only the context relevant to its current task, not the full workflow plan
- **FR-028**: System MUST support step output capture — each completed step records its output path/artifact so downstream steps can reference it

### Key Entities

- **Workflow Definition**: JSON file defining steps, their types, agent assignments, conditions, and dependencies. Located in `workflows/` directory.
- **State (state.json)**: Single source of truth for workflow execution state. Contains step cursor, per-step status, per-agent status within parallel steps, step outputs, and command logs. Located at `.wheel/state.json`.
- **Step**: A single unit of work in a workflow. Types: `agent` (LLM executes), `command` (shell executes), `parallel` (fan-out/fan-in), `approval` (human gate), `branch` (conditional jump), `loop` (repeated execution).
- **Lock**: Filesystem-based mutex using `mkdir` for atomic parallel completion detection. Located at `.wheel/.locks/`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A 3-step linear workflow completes deterministically with zero LLM routing decisions — the LLM only executes step instructions, never decides what to do next
- **SC-002**: A deliberately killed session resumes from the correct step on restart within 2 seconds
- **SC-003**: Parallel fan-in correctly advances only after ALL agents complete, with no race conditions under concurrent SubagentStop events
- **SC-004**: Hook execution latency is under 500ms per invocation (NFR-002)
- **SC-005**: Command steps execute without LLM involvement and their output appears in state.json with exit code and timestamp
- **SC-006**: Branch steps evaluate conditions and jump to the correct target step
- **SC-007**: Loop steps retry until condition met or max_iterations exhausted
- **SC-008**: The example workflow completes end-to-end proving linear steps, command steps, and the full hook integration

## Assumptions

- Claude Code plugin system supports multiple plugins with hooks on the same events (plugins compose)
- `jq` is available on the target system (NFR-004 — listed as a runtime dependency)
- Bash 3.2+ is available (macOS default; NFR-003)
- One workflow runs per Claude Code session (non-goal: multi-workflow sessions)
- The LLM cannot be directly instructed to spawn agents by hooks — hooks can only gate and inject context, so the LLM still decides *when* to spawn but Wheel decides *what instructions* to give
- JSON is used for workflow definitions (not YAML) to avoid parsing dependencies beyond jq
- `state.json` will remain small enough for jq to process in under 500ms even with command logs
