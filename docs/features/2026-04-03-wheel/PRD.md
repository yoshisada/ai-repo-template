# Feature PRD: Wheel — Hook-based Workflow Engine Plugin

**Date**: 2026-04-03
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Kiln's `/build-prd` pipeline currently embeds all orchestration logic in a single skill prompt — the LLM decides step ordering, agent sequencing, and fan-in/fan-out. This is the "LLM as unreliable router" anti-pattern: pipelines are non-deterministic, non-resumable, and prone to context-loss failures on long runs. The LLM must hold the entire workflow plan in memory, and when context fills up, it loses track of where it is.

Claude Code's hook system provides the primitives needed to build a deterministic runtime without the LLM acting as router: `Stop` gates execution, `TeammateIdle` gates agents, `SubagentStart` injects context, `SubagentStop` signals completion, and `SessionStart(resume)` reloads state. Combined with `session_id` and `agent_type` available on every hook input, these primitives are sufficient to build a state machine that feeds the LLM one instruction at a time.

**Wheel** is a new Claude Code plugin (`@yoshisada/wheel`) that provides this deterministic workflow runtime. Future plugins (like kiln) can consume it, but this initial version focuses on proving the core engine with a standalone example workflow.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Create lobster — hook-based workflow engine plugin for Claude Code](.kiln/issues/2026-04-02-lobster-workflow-engine-plugin.md) | — | feature-request | high |

## Problem Statement

Long-running multi-agent pipelines (like `/build-prd`) fail unpredictably because the LLM loses context mid-pipeline and makes wrong routing decisions. There is no way to resume a failed pipeline from its last completed step — the entire run must be restarted. Parallel agent coordination (fan-out/fan-in) relies on the LLM correctly tracking which agents have finished, which is unreliable at scale.

This affects every kiln user running `/build-prd` or any multi-step pipeline. The cost is wasted compute, lost progress, and user frustration when a 30-minute pipeline fails at step 7 of 9 and must restart from scratch.

## Goals

- Deterministic, hook-driven workflow execution — no LLM routing decisions
- Resumable pipelines — crash at step 5, resume at step 5
- Parallel agent fan-out/fan-in with atomic completion tracking
- Per-step context injection — agents receive only what they need, not the full plan
- Approval gates for human-in-the-loop checkpoints
- State persisted to disk as the single source of truth
- Published as `@yoshisada/wheel` Claude Code plugin on npm
- Ships with an example 3-step workflow that proves the engine works end-to-end

## Non-Goals

- **Not a general task queue or job scheduler** — Wheel orchestrates Claude Code agent pipelines, not arbitrary background jobs
- **Not replacing kiln's domain logic** — kiln's 4-gate enforcement, spec templates, QA hooks stay in kiln; Wheel only owns the runtime
- **Not a GUI or dashboard** — state.json is inspectable but there's no web UI planned
- **Not multi-session** — Wheel manages one workflow per Claude Code session (multiple workflows require multiple sessions)

## Requirements

### Functional Requirements

**Core Engine**

- **FR-001** (from: lobster-workflow-engine-plugin.md): Implement a state machine engine (`engine.sh`) that reads a workflow definition and `state.json`, determines the current step, and provides the next instruction to execute
- **FR-002** (from: lobster-workflow-engine-plugin.md): Persist workflow state to `state.json` at the repo root (or `.wheel/state.json`), including current step index, step statuses, agent statuses, and step outputs
- **FR-003** (from: lobster-workflow-engine-plugin.md): Support linear step sequencing — advance a step cursor through an ordered list of steps, injecting the exact next instruction via the `Stop` hook

**Hook Integration**

- **FR-004** (from: lobster-workflow-engine-plugin.md): Implement `Stop` hook handler — gate the parent orchestrator, inject the next step instruction, or allow stop when the workflow is complete
- **FR-005** (from: lobster-workflow-engine-plugin.md): Implement `TeammateIdle` hook handler — gate agents with their agent-specific next task, or allow idle when the step is done
- **FR-006** (from: lobster-workflow-engine-plugin.md): Implement `SubagentStart` hook handler — inject previous step output as `additionalContext` into newly spawned agents
- **FR-007** (from: lobster-workflow-engine-plugin.md): Implement `SubagentStop` hook handler — mark agent done in state.json, check if all parallel agents for the current step have finished, advance to next step if so
- **FR-008** (from: lobster-workflow-engine-plugin.md): Implement `SessionStart(resume)` hook handler — reload state.json and resume from the last completed step

**Parallel Execution**

- **FR-009** (from: lobster-workflow-engine-plugin.md): Support parallel agent fan-out — a single step can spawn multiple agents tracked individually by `agent_type` in state.json
- **FR-010** (from: lobster-workflow-engine-plugin.md): Support atomic fan-in — use `mkdir`-based locking to safely detect when all parallel agents for a step have completed, then advance
- **FR-011** (from: lobster-workflow-engine-plugin.md): Track per-agent state (`working`, `idle`, `done`, `failed`) within parallel steps

**Workflow Definition**

- **FR-012** (from: lobster-workflow-engine-plugin.md): Define a workflow definition format (YAML or JSON) that specifies: step ID, step type (linear/parallel), agent assignments, context dependencies, and approval requirements
- **FR-013** (from: lobster-workflow-engine-plugin.md): Support approval gates — steps that block execution until explicit human approval via TeammateIdle

**Plugin Structure**

- **FR-014** (from: lobster-workflow-engine-plugin.md): Package as a Claude Code plugin with proper `.claude-plugin/plugin.json` manifest
- **FR-015** (from: lobster-workflow-engine-plugin.md): Publish to npm as `@yoshisada/wheel`
- **FR-016** (from: lobster-workflow-engine-plugin.md): Provide a scaffold/init script for consumer projects (similar to kiln's `bin/init.mjs`)

**Command Steps**

- **FR-019**: Support `type: command` steps that execute shell commands directly in the hook script, capture output and exit code, and advance without LLM involvement
- **FR-020**: Consecutive command steps chain — execute in a single hook invocation via `exec "$0"` without returning to the LLM between them
- **FR-021**: Command steps record output, exit code, and timestamp in state.json for auditability

**Command Audit Trail**

- **FR-022**: Implement `PostToolUse(Bash)` hook handler that logs every command the LLM executes during agent steps into the current step's `command_log` array in state.json (command, exit code, timestamp)
- **FR-023**: On session resume, the command log is available so the engine can determine what work was already done in a partially-completed agent step

**Control Flow**

- **FR-024**: Support `type: branch` steps — evaluate a shell condition expression, jump to a target step ID based on exit code (`if_zero` / `if_nonzero`). No LLM involvement.
- **FR-025**: Support `type: loop` steps — repeat a substep (command or agent) until a condition is met (`exit_zero`, `exit_nonzero`) or `max_iterations` is reached. On exhaustion, either `fail` the workflow or `continue` to the next step.
- **FR-026**: Loop substeps can be `type: agent` (LLM retries a task) or `type: command` (re-run a shell command), using the same dispatch logic as top-level steps.

**Context Management**

- **FR-027** (from: lobster-workflow-engine-plugin.md): Per-step context injection — each agent receives only the context relevant to its current task, not the full workflow plan
- **FR-028** (from: lobster-workflow-engine-plugin.md): Step output capture — each completed step records its output path/artifact so downstream steps can reference it

### Non-Functional Requirements

- **NFR-001**: State transitions must be atomic — no partial writes to state.json (write to tmp + rename)
- **NFR-002**: Hook scripts must execute in under 500ms to avoid noticeable latency
- **NFR-003**: Must work with Bash 3.2+ (macOS default) and Bash 5.x (Linux)
- **NFR-004**: No runtime dependencies beyond `jq`, `bash`, and standard Unix tools
- **NFR-005**: Standalone — no dependency on kiln or any other plugin

## User Stories

1. **As a plugin developer**, I want to define a multi-agent pipeline as a declarative workflow file, so I don't embed orchestration logic in LLM prompts.
2. **As a pipeline operator**, I want to inspect `state.json` to see exactly which step is active and which agents are running, so I can debug stuck pipelines.
3. **As a plugin developer**, I want parallel agents to coordinate deterministically, so fan-in doesn't fail when the LLM loses track of agent completion.
4. **As a developer**, I want approval gates in my workflow so I can review artifacts before the pipeline proceeds.
5. **As a developer**, I want a crashed session to resume from the last completed step, so I don't lose progress.
6. **As a pipeline author**, I want command steps that run shell commands without the LLM, so deterministic operations (install, build, test) don't waste tokens.
7. **As a pipeline author**, I want branch and loop control flow, so workflows can react to command results and retry failures.
8. **As a pipeline author**, I want a full command audit log in state.json, so I can see exactly what the LLM ran during agent steps.

## Success Criteria

- **Primary gate**: A sub-agent spawned in an agent team correctly follows the workflow directions injected by the hook — it executes the step instruction it receives, not its own routing logic
- The example workflow completes deterministically with no LLM routing decisions
- Command steps execute without LLM involvement and their output appears in state.json
- A branch step evaluates a condition and jumps to the correct target
- A loop step retries until its condition is met or max iterations exhausted
- A deliberately killed session resumes from the correct step on restart
- Hook latency is under 500ms per invocation
- `state.json` accurately reflects workflow state at all times (including command logs)

## Tech Stack

- **Bash 3.2+/5.x** — hook scripts and engine core
- **jq** — JSON state manipulation
- **Node.js 18+** — `bin/init.mjs` scaffold script, `package.json` for npm distribution
- **Claude Code plugin system** — hooks.json, plugin.json
- **Filesystem** — `state.json` for persistence, `mkdir` for atomic locking

## Risks & Open Questions

1. **Hook latency budget**: Complex state transitions (especially parallel fan-in with locking) may push hook execution beyond 500ms. Need to profile early.
2. **Hook capability gaps**: Claude Code hooks can gate and inject context, but can they trigger agent spawning? If not, the LLM still decides *when* to spawn — Wheel only decides *what instructions* to give. Need to validate this assumption.
3. **State corruption**: Concurrent hook invocations (e.g., two SubagentStop hooks firing simultaneously) could race on state.json writes. The `mkdir` lock must be bulletproof.
4. **Workflow definition format**: YAML vs JSON — YAML is more human-readable but adds a parsing dependency. JSON works with `jq` out of the box.
5. **Example workflow design**: What's the simplest meaningful workflow that demonstrates linear steps, parallel agents, and approval gates without depending on kiln?
6. **Plugin composition**: Can a Claude Code project use multiple plugins with hooks on the same events? Need to verify for future consumer plugins.
