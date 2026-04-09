# Feature PRD: Wheel Team Primitives — Parallel Agent Execution in Workflows

**Date**: 2026-04-09
**Status**: Draft
**Parent PRD**: [Wheel — Hook-based Workflow Engine Plugin](../2026-04-03-wheel/PRD.md)

## Overview

Add four new step types to the wheel workflow engine that enable parallel agent execution via Claude Code agent teams. Workflows can create teams, spawn teammates that each run a sub-workflow, wait for all teammates to complete, and clean up — all declaratively in workflow JSON. This turns wheel from a purely sequential engine into one that supports fan-out/fan-in parallelism while keeping the deterministic, hook-driven execution model.

## Motivation

Wheel workflows currently execute steps one at a time. Agent steps are powerful but sequential — a workflow that needs to process 15 pages runs 15 agent steps back-to-back. For workloads that are naturally parallel (building N pages, running N test suites, auditing N modules), this is unnecessarily slow.

Claude Code already has agent teams (TeamCreate, Agent with team_name, TaskCreate, SendMessage). But using them requires a skill or build-prd-style orchestrator to manage the lifecycle manually. There's no way to express "fan out to N agents, wait for all, collect results" in a workflow definition.

By adding team primitives to wheel, any workflow can leverage parallelism without custom orchestration code. The workflow author declares the structure; the engine handles team lifecycle, agent spawning, task tracking, and result collection.

## Problem Statement

Wheel workflows that need to process collections of independent items (pages, components, test files, modules) must do so sequentially. A 15-item workload that takes 5 minutes per item runs for 75 minutes instead of 15. There's no way to express parallel execution in the workflow JSON. Users who need parallelism must abandon wheel and use raw agent teams with manual orchestration, losing wheel's deterministic step tracking, hook interception, and state management.

## Goals

- Enable parallel agent execution within wheel workflows via declarative step types
- Keep the workflow JSON format simple — team primitives are just steps with a `type` field like everything else
- Preserve wheel's hook-driven execution model — team steps are intercepted and managed by the engine like any other step
- Support both static teammate spawning (known count at authoring time) and dynamic spawning (count determined at runtime from a previous step's output)
- Collect results from all teammates into a predictable output location for downstream steps
- Handle teammate failures gracefully — partial results are collected, failures are reported

## Non-Goals

- Real-time inter-agent communication during execution (teammates run independently; use SendMessage outside wheel if needed)
- Nested teams (a teammate spawning its own sub-team) — one level of fan-out only for v1
- Load balancing or work stealing between teammates
- Shared mutable state between teammates (each runs in isolation with its own sub-workflow state)
- Replacing the existing `"type": "workflow"` step (that stays for inline sequential composition)

## User Stories

### US-1: Static Fan-Out
As a workflow author, I want to define 3 teammate steps in my workflow JSON that each run the same sub-workflow with different assigned work, so I can parallelize a known workload without writing orchestration code.

### US-2: Dynamic Fan-Out
As a workflow author, I want to define a single teammate step with `loop_from` that reads a previous step's output and spawns one teammate per entry, so the parallelism scales with the workload size at runtime.

### US-3: Wait and Collect
As a workflow author, I want a step that blocks until all teammates finish and collects their outputs into a directory, so downstream steps can aggregate results.

### US-4: Failure Resilience
As a workflow author, I want the pipeline to continue even if some teammates fail, collecting partial results and reporting which teammates succeeded and which failed, so one bad page doesn't block the entire workflow.

### US-5: Sub-Workflow Reuse
As a workflow author, I want teammates to run existing workflow JSON files as sub-workflows, so I can reuse workflow definitions across different team configurations without duplication.

## Functional Requirements

### Step Type: `team-create`

**FR-001** — A new step type `team-create` MUST create a Claude Code agent team via `TeamCreate` and store the team name in the workflow state for reference by subsequent steps.

**FR-002** — The `team-create` step MUST accept a `team_name` field (string). If omitted, the engine generates a name from the workflow name and step ID: `{workflow-name}-{step-id}`.

**FR-003** — The `team-create` step MUST be a no-op if a team with the same name already exists (idempotent). It MUST NOT error.

**FR-004** — The workflow state MUST record the team name under `teams.{step-id}` so that `teammate`, `team-wait`, and `team-delete` steps can reference it via the `team` field.

### Step Type: `teammate`

**FR-005** — A new step type `teammate` MUST spawn a single Claude Code agent (via the `Agent` tool) that joins the team created by the referenced `team-create` step and runs a sub-workflow.

**FR-006** — The `teammate` step MUST accept these fields:
  - `team` (string, required) — references the `id` of a `team-create` step
  - `workflow` (string, required) — name or path of the sub-workflow JSON to run (same resolution as `"type": "workflow"` steps — local `workflows/` or `plugin:name`)
  - `context_from` (array of step IDs, optional) — outputs from these parent steps are passed as context to the sub-workflow
  - `assign` (object, optional) — arbitrary JSON payload passed to the agent as its work assignment (e.g., `{"pages": [0, 1, 2]}`)
  - `name` (string, optional) — human-readable agent name. If omitted, generated from step ID

**FR-007** — The `teammate` step MUST create a `TaskCreate` entry for the spawned agent so the team-wait step can track completion.

**FR-008** — The `teammate` step MUST spawn the agent with `run_in_background: true`. The parent workflow advances to the next step immediately after spawning — it does NOT wait for the teammate to finish.

**FR-009** — The spawned agent MUST receive a prompt that includes:
  a. The sub-workflow to execute (via `/wheel-run` or direct execution)
  b. Context from `context_from` steps (output file contents)
  c. The `assign` payload so it knows which portion of work it owns
  d. Instructions to mark its task as completed when the sub-workflow finishes
  e. Instructions to write its output to `.wheel/outputs/team-{team-name}/{agent-name}/`

**FR-010** — The agent MUST run with `mode: "bypassPermissions"` to avoid blocking on permission prompts during automated execution.

### Dynamic Spawning: `loop_from`

**FR-011** — The `teammate` step MUST accept an optional `loop_from` field (string) — the ID of a previous step whose output is a JSON array.

**FR-012** — When `loop_from` is present, the engine MUST read the referenced step's output file, parse it as a JSON array, and spawn one teammate per array entry. Each teammate receives its array entry as the `assign` payload.

**FR-013** — When `loop_from` is present, a `max_agents` field (integer, optional, default 5) MUST cap the number of spawned agents. If the array has more entries than `max_agents`, entries MUST be distributed across agents in round-robin groups (e.g., 15 entries with max 5 agents = 3 entries per agent).

**FR-014** — Each dynamically spawned agent MUST receive a unique name: `{step-id}-{index}` (e.g., `spawn-builders-0`, `spawn-builders-1`).

### Step Type: `team-wait`

**FR-015** — A new step type `team-wait` MUST block the parent workflow until all teammates on the referenced team have completed their tasks (all tasks show status `completed` or `failed`).

**FR-016** — The `team-wait` step MUST accept these fields:
  - `team` (string, required) — references the `id` of a `team-create` step
  - `collect_to` (string, optional) — directory path where teammate outputs are collected. If omitted, outputs remain in `.wheel/outputs/team-{team-name}/{agent-name}/`

**FR-017** — The engine MUST poll `TaskList` to check teammate completion status. Poll interval: 30 seconds.

**FR-018** — When all teammates are done, the `team-wait` step MUST write a summary to its output file containing:
  - Total teammates spawned
  - Completed count
  - Failed count
  - Per-teammate: name, status, output path, duration
  - If `collect_to` is set: copy each teammate's output directory into the collect path

**FR-019** — The `team-wait` step MUST NOT fail if some teammates failed. It reports partial results and advances the workflow. The downstream step decides how to handle failures.

### Step Type: `team-delete`

**FR-020** — A new step type `team-delete` MUST gracefully shut down all agents on the team and clean up via `TeamDelete`.

**FR-021** — The `team-delete` step MUST send shutdown requests to all teammates, wait for confirmation, then call `TeamDelete` to remove team and task directories.

**FR-022** — The `team-delete` step MUST accept a `team` field (string, required) referencing the `team-create` step ID.

**FR-023** — If teammates are still running when `team-delete` is reached (e.g., the workflow was cancelled or `team-wait` was skipped), the step MUST force-terminate remaining agents before cleanup.

### Engine Integration

**FR-024** — The wheel engine (hooks, state management, cursor advancement) MUST recognize all four new step types and handle them in the PostToolUse hook alongside existing `command`, `agent`, `workflow`, and `branch` types.

**FR-025** — Team-related state (team name, teammate task IDs, teammate statuses) MUST be stored in the workflow state file under a `teams` key, following the existing state file format.

**FR-026** — The `team-wait` step MUST be implemented in the PostToolUse hook as a polling loop. The hook checks teammate status on each invocation and only advances the cursor when all teammates are done. Between polls, the hook returns without advancing.

**FR-027** — Teammate sub-workflows MUST run with their own independent state files (`.wheel/state_{agent-id}.json`). The parent workflow's state file tracks the team, not the individual sub-workflow progress.

**FR-028** — If the parent workflow is stopped (via `/wheel-stop`), all active teammates MUST be stopped and their teams cleaned up as part of the cascade stop logic.

### Sub-Workflow Context Passing

**FR-029** — Context from `context_from` steps MUST be passed to the teammate by writing a combined context file to `.wheel/outputs/team-{team-name}/{agent-name}/context.json` containing the referenced step outputs.

**FR-030** — The `assign` payload MUST be written to `.wheel/outputs/team-{team-name}/{agent-name}/assignment.json` so the sub-workflow can read it in its first step.

**FR-031** — The sub-workflow's agent steps MUST be able to reference `context.json` and `assignment.json` as if they were outputs from previous steps (via a synthetic `_context` and `_assignment` step ID in `context_from`).

## Non-Functional Requirements

**NFR-001** — The `teammate` spawn step MUST complete in under 5 seconds (it only triggers the spawn, doesn't wait for execution).

**NFR-002** — The `team-wait` polling MUST NOT consume excessive resources. Poll via `TaskList` at 30-second intervals, not continuous loops.

**NFR-003** — Team state in the workflow state file MUST NOT exceed 10KB even with 10 teammates (store references, not full outputs).

**NFR-004** — All team operations MUST be idempotent. Re-running a `team-create` on an existing team is a no-op. Re-running `team-delete` on a deleted team is a no-op.

**NFR-005** — Teammate output directories MUST follow a predictable naming convention (`.wheel/outputs/team-{team-name}/{agent-name}/`) so downstream steps can glob for results without knowing the exact agent names.

## Tech Stack

Inherited from wheel:
- Bash 5.x (hook scripts, engine libs)
- jq (JSON parsing/manipulation in hooks)
- File-based JSON state (`.wheel/state_*.json`)

Additions:
- Claude Code agent teams API (`TeamCreate`, `TaskCreate`, `TaskList`, `TaskUpdate`, `TeamDelete`, `Agent`, `SendMessage`)
- These are already available in Claude Code — no new dependencies

## Success Criteria

- A workflow with `team-create` → 3x `teammate` → `team-wait` → `team-delete` spawns 3 agents, waits for all to finish, and collects outputs — all via the hook system
- A workflow with `loop_from` dynamically spawns the correct number of agents based on a previous step's JSON array output
- `team-wait` correctly blocks until all teammates complete, even if some fail
- `team-delete` cleanly shuts down all agents and removes team resources
- Existing workflow types (`command`, `agent`, `workflow`, `branch`) continue to work unchanged
- A stopped parent workflow cascades stop to all active teammates

## Risks & Open Questions

- **Hook execution context**: The `team-wait` polling needs the hook to fire periodically even when no tool calls are happening. Current hooks only fire on tool use — may need a timer-based mechanism or a "check status" command that the engine runs periodically.
- **Agent spawn reliability**: If a teammate spawn fails (e.g., rate limits on agent creation), the workflow needs a retry or graceful degradation path.
- **State file size**: With many teammates, the state file grows. The `teams` key should store minimal data (task IDs and status, not full outputs).
- **Nested teams**: This PRD explicitly excludes nested teams (a teammate spawning its own sub-team). If needed later, the state model would need a parent-child relationship between teams.
- **Sub-workflow hooks**: Teammate sub-workflows create their own state files. The parent workflow's PostToolUse hook must not interfere with teammate hooks. The existing per-agent state resolution (guard.sh) should handle this via owner_session_id/owner_agent_id matching.
