# Interface Contracts: Wheel TypeScript Rewrite

**Feature**: `002-wheel-ts-rewrite`
**Last Updated**: 2026-04-29

This document defines exact function signatures for every exported function in `plugin-wheel/src/`. All implementations — including parallel sub-agents — MUST match these signatures exactly. Signatures are the single source of truth.

---

## §1. `src/shared/jq.ts` — Pure-TS jq Wrappers

These are **pure TypeScript** — no `child_process.exec` of `jq`. They replicate the jq CLI's path-query and path-update semantics using JavaScript's native JSON traversal. All functions throw `ValidationError` on malformed JSON or invalid paths.

### `jqQuery<T>(json: unknown, path: string): T`

Evaluate a jq path expression against `json` and return the result cast to type `T`.

| Param | Type | Description |
|-------|------|-------------|
| `json` | `unknown` | Parsed JSON value (already `JSON.parse`'d) |
| `path` | `string` | jq path expression, e.g. `.steps[0].status` |

**Returns**: `T` — the value at the jq path. Throws `ValidationError` if path is invalid or returns `null`.

**Throws**: `ValidationError` with `context: { path, reason }`

**Examples**:
```typescript
jqQuery<string>(state, '.status')           // → "running"
jqQuery<number>(workflow, '.steps | length') // → 3
jqQuery<unknown[]>(state, '.steps')        // → Step[]
```

### `jqQueryRaw(json: unknown, path: string): string`

Same as `jqQuery` but returns the raw JSON string representation of the result.

| Param | Type | Description |
|-------|------|-------------|
| `json` | `unknown` | Parsed JSON value |
| `path` | `string` | jq path expression |

**Returns**: `string` — JSON string of the result (single-line, jq-compatible format).

### `jqUpdate(json: unknown, path: string, value: unknown): string`

Return a new JSON string with `value` assigned at the jq `path` (analogous to `jq -c '.|path = value'`).

| Param | Type | Description |
|-------|------|-------------|
| `json` | `unknown` | Parsed JSON value |
| `path` | `string` | jq path expression (must be an lvalue) |
| `value` | `unknown` | Value to set at path |

**Returns**: `string` — new JSON string (single-line). Throws `ValidationError` if path is not an lvalue.

---

## §2. `src/shared/fs.ts` — Filesystem Helpers

All functions use `fs/promises`. No shell command substitution.

### `atomicWrite(path: string, content: string): Promise<void>`

Write `content` to `path` atomically: write to temp file (same directory as `path`), then `fs.rename` to final path. Guarantees no partial file is readable on disk.

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute path to target file |
| `content` | `string` | Content to write |

**Returns**: `Promise<void>` — resolves on success, rejects on I/O error.

**Throws**: `WheelError` with `code: 'FS_WRITE'` on failure.

### `mkdirp(path: string): Promise<void>`

Recursively create directory and all ancestors. Idempotent — succeeds even if directory already exists.

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute directory path |

**Returns**: `Promise<void>`.

### `fileRead(path: string): Promise<string>`

Read file contents as string. Rejects if file does not exist.

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute path |

**Returns**: `Promise<string>` — file contents.

**Throws**: `StateNotFoundError` if file missing.

### `fileExists(path: string): Promise<boolean>`

Check if a file exists (no throw on missing).

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute path |

**Returns**: `Promise<boolean>`.

---

## §3. `src/shared/state.ts` — State File Persistence

Thin wrapper over `fs.ts` + `jq.ts` for the `.wheel/state_*.json` file format.

### `stateRead(path: string): Promise<WheelState>`

Read and parse a wheel state file.

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute path to `.wheel/state_*.json` |

**Returns**: `Promise<WheelState>`.

**Throws**: `StateNotFoundError` if file missing. `ValidationError` if file is not valid JSON.

### `stateWrite(path: string, state: WheelState): Promise<void>`

Write state to file atomically using `atomicWrite`. The `updated_at` field is set to the current UTC timestamp before writing.

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute path to state file |
| `state` | `WheelState` | Full state object to write |

**Returns**: `Promise<void>`.

---

## §4. `src/shared/error.ts` — Error Types

### `WheelError` class

```
extends Error
code: string                    // Machine-readable error code
context: Record<string, unknown> // Structured diagnostic data
```

### `StateNotFoundError extends WheelError`

`code = 'STATE_NOT_FOUND'`. Thrown when a state file is missing.

### `ValidationError extends WheelError`

`code = 'VALIDATION_ERROR'`. Thrown when JSON is malformed, a jq path is invalid, or schema validation fails.

### `LockError extends WheelError`

`code = 'LOCK_ERROR'`. Thrown when mkdir-based locking fails (e.g., lock held, permission denied).

---

## §5. `src/lib/state.ts` — State Operations

All functions in this module operate on the `WheelState` interface. They read-modify-write via `stateRead` + `stateWrite`. Every mutation sets `updated_at` to current UTC ISO-8601.

### `stateInit(params: StateInitParams): Promise<void>`

Initialize a new state file from a workflow definition. Creates directory, sets `status: "running"`, `cursor: 0`, `started_at`, `updated_at`, and builds the `steps[]` array from the workflow's step definitions. See `lib/state.sh::state_init()` for exact JSON structure.

| Param | Type | Description |
|-------|------|-------------|
| `params.stateFile` | `string` | Absolute path to state file to create |
| `params.workflow` | `WorkflowDefinition` | Parsed workflow JSON |
| `params.sessionId` | `string` | Owner session ID |
| `params.agentId` | `string` | Owner agent ID (empty string for main orchestrator) |
| `params.workflowFile?` | `string` | Path to workflow file on disk |
| `params.parentWorkflow?` | `string` | Path to parent state file for child workflows (FR-016) |
| `params.sessionRegistry?` | `SessionRegistry` | Pre-built registry JSON for `resolve_inputs` (FR-G2-3) |

**Returns**: `Promise<void>`. Writes the state file atomically.

### `stateGetCursor(state: WheelState): number`

| Param | Type | Description |
|-------|------|-------------|
| `state` | `WheelState` | Parsed state object |

**Returns**: `number` — current step cursor (0-based).

### `stateSetCursor(stateFile: string, cursor: number): Promise<void>`

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path to state file |
| `cursor` | `number` | New cursor value |

**Returns**: `Promise<void>`. Reads, updates `cursor` + `updated_at`, writes atomically.

### `stateGetStepStatus(state: WheelState, stepIndex: number): StepStatus`

| Param | Type | Description |
|-------|------|-------------|
| `state` | `WheelState` | Parsed state object |
| `stepIndex` | `number` | 0-based step index |

**Returns**: `StepStatus` — `"pending" | "working" | "done" | "failed"`.

### `stateSetStepStatus(stateFile: string, stepIndex: number, status: StepStatus): Promise<void>`

Sets step status. If `status === "working"`, sets `started_at`. If `status === "done" | "failed"`, sets `completed_at`. Always updates `updated_at`.

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path |
| `stepIndex` | `number` | 0-based step index |
| `status` | `StepStatus` | New status |

**Returns**: `Promise<void>`.

### `stateGetAgentStatus(state: WheelState, stepIndex: number, agentType: string): AgentStatus`

| Param | Type | Description |
|-------|------|-------------|
| `state` | `WheelState` | Parsed state object |
| `stepIndex` | `number` | 0-based step index |
| `agentType` | `string` | Agent type key within `steps[].agents{}` |

**Returns**: `AgentStatus` — `"pending" | "working" | "idle" | "done" | "failed"`.

**Throws**: `StateNotFoundError` if agent key not found.

### `stateSetAgentStatus(stateFile: string, stepIndex: number, agentType: string, status: AgentStatus): Promise<void>`

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path |
| `stepIndex` | `number` | 0-based step index |
| `agentType` | `string` | Agent type key |
| `status` | `AgentStatus` | New status |

**Returns**: `Promise<void>`.

### `stateSetStepOutput(stateFile: string, stepIndex: number, output: unknown): Promise<void>`

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path |
| `stepIndex` | `number` | 0-based step index |
| `output` | `unknown` | Output value/path to record |

**Returns**: `Promise<void>`.

### `stateAppendCommandLog(stateFile: string, stepIndex: number, entry: CommandLogEntry): Promise<void>`

Append `{command, exit_code, timestamp}` to `steps[stepIndex].command_log[]`.

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path |
| `stepIndex` | `number` | 0-based step index |
| `entry` | `CommandLogEntry` | `{ command: string, exit_code: number, timestamp: string }` |

**Returns**: `Promise<void>`.

### `stateGetCommandLog(state: WheelState, stepIndex: number): CommandLogEntry[]`

| Param | Type | Description |
|-------|------|-------------|
| `state` | `WheelState` | Parsed state object |
| `stepIndex` | `number` | 0-based step index |

**Returns**: `CommandLogEntry[]`.

### `stateSetTeam(stateFile: string, stepId: string, teamName: string): Promise<void>`

FR-025. Record a team in `state.teams[stepId]`.

### `stateGetTeam(state: WheelState, stepId: string): Team`

### `stateAddTeammate(stateFile: string, teamStepId: string, teammate: TeammateEntry): Promise<void>`

### `stateUpdateTeammateStatus(stateFile: string, teamStepId: string, agentName: string, status: TeammateStatus): Promise<void>`

### `stateGetTeammates(state: WheelState, teamStepId: string): Record<string, TeammateEntry>`

### `stateRemoveTeam(stateFile: string, stepId: string): Promise<void>`

### `stateSetAwaitingUserInput(stateFile: string, stepIndex: number, reason: string): Promise<void>`

FR-003/004 (wheel-user-input). Sets `awaiting_user_input: true`, `awaiting_user_input_since: <now>`, `awaiting_user_input_reason: reason`.

### `stateClearAwaitingUserInput(stateFile: string, stepIndex: number): Promise<void>`

FR-004/008 (wheel-user-input). Clears `awaiting_user_input = false`, `awaiting_user_input_since = null`, `awaiting_user_input_reason = null`. Idempotent.

### `stateSetResolvedInputs(stateFile: string, stepIndex: number, resolvedMap: unknown): Promise<void>`

FR-§4.1 (wheel-typed-schema-locality). Persists dispatch-time resolved inputs onto the per-step record.

### `stateSetContractEmitted(stateFile: string, stepIndex: number, emitted: boolean): Promise<void>`

FR-§4.2. Mark Stop-hook contract block as emitted (emit-once-per-step-entry).

### `stateGetContractEmitted(stateFile: string, stepIndex: number): boolean`

FR-§4.3. Read `contract_emitted` flag. Returns `false` for missing/unreadable files (backward compat with legacy state).

---

## §6. `src/lib/engine.ts` — Core Engine

### `engineInit(workflowFile: string, stateFile: string): Promise<void>`

Load workflow definition and initialize globals (`WORKFLOW`, `STATE_DIR`, `STATE_FILE`). Reads from `stateFile.workflow_definition` if present (preferred), else falls back to loading `workflowFile` from disk.

| Param | Type | Description |
|-------|------|-------------|
| `workflowFile` | `string` | Path to workflow JSON file |
| `stateFile` | `string` | Absolute path to `.wheel/state_*.json` |

**Returns**: `Promise<void>`. Sets module-level state.

**Throws**: `StateNotFoundError` / `ValidationError` on failure.

### `engineKickstart(stateFile: string): Promise<string | void>`

Kickstart the workflow by dispatching the first step inline. For `command`/`loop`/`branch` steps: executes them immediately in the hook (no LLM). For `agent` steps: sets step to `pending` and returns the instruction string.

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path to state file |

**Returns**: `Promise<string | void>` — instruction string for agent steps, void for others.

### `engineCurrentStep(): Promise<WorkflowStep | null>`

Read state, get current step from cursor, return step definition.

**Returns**: `Promise<WorkflowStep>` — current step definition.

**Returns**: `Promise<null>` — if cursor >= step count (workflow complete).

**Throws**: `StateNotFoundError` if state file unreadable.

### `engineHandleHook(hookType: HookType, hookInput: HookInput): Promise<HookOutput>`

Main entry point called by each hook handler. Routes by `hookType` to appropriate handler. Returns JSON response for Claude Code to consume.

| Param | Type | Description |
|-------|------|-------------|
| `hookType` | `HookType` | `"post_tool_use" \| "teammate_idle" \| "session_start" \| "stop" \| "subagent_start" \| "subagent_stop"` |
| `hookInput` | `HookInput` | Parsed JSON from Claude Code hook stdin |

**Returns**: `Promise<HookOutput>` — JSON response. Throws on unrecoverable error (logs and returns approve).

---

## §7. `src/lib/dispatch.ts` — Step Dispatcher

### `dispatchStep(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

Routes `step` by `step.type` to the appropriate sub-handler.

| Param | Type | Description |
|-------|------|-------------|
| `step` | `WorkflowStep` | Step definition |
| `hookType` | `HookType` | Current hook type |
| `hookInput` | `HookInput` | Hook stdin JSON |
| `stateFile` | `string` | Absolute path |
| `stepIndex` | `number` | 0-based step index |

**Returns**: `Promise<HookOutput>`.

### `dispatchAgent(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-003. Handles `type: "agent"` steps. Gates orchestrator, injects instruction. Called from `engineHandleHook` PostToolUse path.

### `dispatchCommand(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-019. Executes `command` steps inline via `child_process.exec`. Captures stdout/stderr/exit_code, records in state. No LLM involvement.

### `dispatchWorkflow(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-014. Handles `type: "workflow"` steps. Creates child state file. Re-invokes `engineKickstart` on child.

### `dispatchTeamCreate(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-025. Creates a team in state, records team metadata.

### `dispatchTeammate(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-025. Adds a teammate entry to an existing team in state.

### `dispatchTeamWait(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-026. Polls teammate completion on each PostToolUse. Gates orchestrator until all teammates complete.

### `dispatchTeamDelete(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-025. Removes a team from state after completion.

### `dispatchBranch(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-024. Evaluates `step.condition` shell expression. Jumps to `step.if_zero` or `step.if_nonzero` target.

### `dispatchLoop(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-025. Manages loop state (`loop_iteration`). Evaluates condition on each dispatch. Respects `max_iterations` and `on_exhaustion: "fail" | "continue"`.

### `dispatchParallel(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-009. Fan-out: marks all agents in `step.agents` as `working`. Uses `lock.ts` for atomic fan-in detection.

### `dispatchApproval(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>`

FR-013. Blocks orchestrator. Signals user approval required.

### `_hydrateAgentStep(step: WorkflowStep, state: WheelState, workflow: WorkflowDefinition, stateFile: string, stepIndex: number): Promise<string>`

FR-G3-1/FR-G3-4. Resolves `step.inputs{}` against state + workflow + session_registry. Returns JSON string of resolved map. On failure: marks step failed, returns error string.

---

## §8. `src/lib/workflow.ts` — Workflow Definition

### `workflowLoad(path: string): Promise<WorkflowDefinition>`

Load and validate a workflow JSON file. Checks: file exists, valid JSON, has `name`, has steps, each step has `id` and `type`, branch targets exist.

| Param | Type | Description |
|-------|------|-------------|
| `path` | `string` | Absolute path to workflow JSON file |

**Returns**: `Promise<WorkflowDefinition>`.

**Throws**: `StateNotFoundError` if file missing. `ValidationError` if invalid.

### `workflowGetStep(workflow: WorkflowDefinition, index: number): WorkflowStep`

| Param | Type | Description |
|-------|------|-------------|
| `workflow` | `WorkflowDefinition` | Parsed workflow |
| `index` | `number` | 0-based step index |

**Returns**: `WorkflowStep`.

**Throws**: `ValidationError` if index out of range.

### `workflowStepCount(workflow: WorkflowDefinition): number`

| Param | Type | Description |
|-------|------|-------------|
| `workflow` | `WorkflowDefinition` | Parsed workflow |

**Returns**: `number` — total step count.

### `workflowGetBranchTarget(workflow: WorkflowDefinition, stepId: string, branchExitCode: number): WorkflowStep | null>`

FR-024. Given a branch step's `stepId`, determine the target step based on `branchExitCode`. Returns `null` if target is "END" or missing.

---

## §9. `src/lib/context.ts` — Context Building

### `contextBuild(step: WorkflowStep, state: WheelState, resolvedInputs: unknown): Promise<string>`

Build `additional_context` string injected into agents via hook responses. Includes: step description, previous step output, command log for this step, resolved inputs, loop iteration context.

| Param | Type | Description |
|-------|------|-------------|
| `step` | `WorkflowStep` | Current step |
| `state` | `WheelState` | Current state |
| `resolvedInputs` | `unknown` | Output of `_hydrateAgentStep` |

**Returns**: `Promise<string>` — plain text context block.

---

## §10. `src/lib/lock.ts` — mkdir-based Locking

### `acquireLock(lockPath: string, ttlMs?: number): Promise<boolean>`

Attempt to acquire an exclusive lock using `mkdir`. Returns `true` if acquired, `false` if already held (another process won). TTL cleanup via setTimeout (for crash cleanup).

| Param | Type | Description |
|-------|------|-------------|
| `lockPath` | `string` | Absolute path to lock file dir |
| `ttlMs` | `number` | TTL in ms (default: 30000) |

**Returns**: `Promise<boolean>` — `true` acquired, `false` held.

### `releaseLock(lockPath: string): Promise<void>`

Remove the lock directory. Idempotent.

| Param | Type | Description |
|-------|------|-------------|
| `lockPath` | `string` | Absolute path to lock file dir |

**Returns**: `Promise<void>`.

### `withLock<T>(lockPath: string, fn: () => Promise<T>): Promise<T>`

Acquire lock, execute `fn`, release lock. Throws `LockError` if cannot acquire.

| Param | Type | Description |
|-------|------|-------------|
| `lockPath` | `string` | Lock path |
| `fn` | `() => Promise<T>` | Async function to execute under lock |

**Returns**: `Promise<T>` — result of `fn`.

---

## §11. `src/lib/guard.ts` — Session Guard

### `guardCheck(stateFile: string, stepIndex: number): Promise<GuardResult>`

FR-004/FR-005. TeammateIdle guard: check if current step is a team-wait or agent step. If team-wait: check if all teammates are done. Return `approve` or gate with instruction.

| Param | Type | Description |
|-------|------|-------------|
| `stateFile` | `string` | Absolute path |
| `stepIndex` | `number` | 0-based step index |

**Returns**: `Promise<GuardResult>` — `{ decision: "approve" | "block", instruction?: string }`.

---

## §12. `src/lib/preprocess.ts` — Variable Substitution

### `preprocess(workflow: WorkflowDefinition, registry: SessionRegistry): WorkflowDefinition`

Substitute `${WHEEL_PLUGIN_<name>}` and `${WORKFLOW_PLUGIN_DIR}` tokens in all string fields of the workflow definition using the session registry.

| Param | Type | Description |
|-------|------|-------------|
| `workflow` | `WorkflowDefinition` | Raw workflow JSON |
| `registry` | `SessionRegistry` | Plugin-dir registry |

**Returns**: `WorkflowDefinition` — new object with substitutions applied (no mutation of input).

---

## §13. `src/lib/registry.ts` — Cross-Plugin Registry

### `buildSessionRegistry(): Promise<SessionRegistry>`

FR-F1. Discover all installed plugin directories under `~/.claude/plugins/cache/`. Return a map of plugin name → absolute plugin directory path.

**Returns**: `Promise<SessionRegistry>` — `{ [pluginName: string]: string }`.

### `resolvePluginPath(pluginName: string, registry: SessionRegistry): string | null>`

Given a plugin name, return its absolute directory path from the registry.

| Param | Type | Description |
|-------|------|-------------|
| `pluginName` | `string` | e.g., `"kiln"`, `"shelf"` |
| `registry` | `SessionRegistry` | Registry map |

**Returns**: `string | null` — absolute path or null if not found.

---

## §14. `src/lib/resolve_inputs.ts` — Agent Input Resolution

### `resolveInputs(inputs: Record<string, string>, state: WheelState, workflow: WorkflowDefinition, registry: SessionRegistry): ResolvedInputs`

FR-G3-4. Resolve the `inputs` map of a step against state, workflow, and registry. Supports variable references: `$(state.path)`, `$(workflow.path)`, `$plugin(<name>.path)`.

| Param | Type | Description |
|-------|------|-------------|
| `inputs` | `Record<string, string>` | Step inputs map |
| `state` | `WheelState` | Current state |
| `workflow` | `WorkflowDefinition` | Current workflow |
| `registry` | `SessionRegistry` | Plugin registry |

**Returns**: `ResolvedInputs` — resolved values map.

---

## §15. `src/hooks/*.ts` — CLI Entry Points

Each hook handler is a standalone CLI script invoked by Claude Code via `hooks/hooks.json`. They read hook input from stdin, call `engineHandleHook`, and write JSON response to stdout.

### Hook signature (all 6)

```typescript
// src/hooks/post-tool-use.ts (and all other hooks)
async function main(): Promise<void> {
  const input: HookInput = JSON.parse(await readStdin());
  const output = await engineHandleHook('post_tool_use', input);
  console.log(JSON.stringify(output));
}
main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
```

| File | Hook Type | Claude Code Event |
|------|-----------|-------------------|
| `post-tool-use.ts` | `"post_tool_use"` | PostToolUse (Bash, Write, Edit, Agent, etc.) |
| `stop.ts` | `"stop"` | Stop |
| `teammate-idle.ts` | `"teammate_idle"` | TeammateIdle |
| `subagent-start.ts` | `"subagent_start"` | SubagentStart |
| `subagent-stop.ts` | `"subagent_stop"` | SubagentStop |
| `session-start.ts` | `"session_start"` | SessionStart (resume) |

---

## §16. `src/index.ts` — CLI Router

```typescript
// src/index.ts
async function main(): Promise<void> {
  const hookType = process.argv[2]; // e.g. "post_tool_use"
  const input: HookInput = JSON.parse(await readStdin());
  const output = await engineHandleHook(hookType, input);
  console.log(JSON.stringify(output));
}
```

Each `src/hooks/*.ts` file is a separate compiled binary. `src/index.ts` is an optional unified entry point for direct invocation.

---

## §17. Core TypeScript Interfaces

```typescript
// Shared across all modules
type StepStatus = 'pending' | 'working' | 'done' | 'failed';
type AgentStatus = 'pending' | 'working' | 'idle' | 'done' | 'failed';
type TeammateStatus = 'pending' | 'running' | 'completed' | 'failed';
type HookType = 'post_tool_use' | 'stop' | 'teammate_idle' | 'subagent_start' | 'subagent_stop' | 'session_start';

interface WheelState {
  workflow_name: string;
  workflow_version: string;
  workflow_file: string;
  workflow_definition: WorkflowDefinition | null;
  status: 'running' | 'completed' | 'failed';
  cursor: number;
  owner_session_id: string;
  owner_agent_id: string;
  started_at: string;       // ISO-8601 UTC
  updated_at: string;        // ISO-8601 UTC
  steps: Step[];
  teams: Record<string, Team>;
  session_registry: SessionRegistry | null;
}

interface Step {
  id: string;
  type: StepType;
  status: StepStatus;
  started_at: string | null;
  completed_at: string | null;
  output: unknown;
  command_log: CommandLogEntry[];
  agents: Record<string, Agent>;
  loop_iteration: number;
  awaiting_user_input: boolean;
  awaiting_user_input_since: string | null;
  awaiting_user_input_reason: string | null;
  resolved_inputs: unknown | null;
  contract_emitted: boolean;
}

interface Agent {
  status: AgentStatus;
  started_at: string | null;
  completed_at: string | null;
}

interface CommandLogEntry {
  command: string;
  exit_code: number;
  timestamp: string;
}

interface Team {
  team_name: string;
  created_at: string;
  teammates: Record<string, TeammateEntry>;
}

interface TeammateEntry {
  task_id: string;
  status: TeammateStatus;
  agent_id: string;
  output_dir: string;
  assign: unknown;
  started_at: string | null;
  completed_at: string | null;
}

type StepType = 'agent' | 'command' | 'parallel' | 'approval' | 'branch' | 'loop' | 'workflow' | 'team-create' | 'teammate' | 'team-wait' | 'team-delete';

interface WorkflowStep {
  id: string;
  type: StepType;
  instruction?: string;
  command?: string;
  condition?: string;
  if_zero?: string;
  if_nonzero?: string;
  max_iterations?: number;
  on_exhaustion?: 'fail' | 'continue';
  agents?: string[];
  inputs?: Record<string, string>;
  [key: string]: unknown; // Allow step-specific fields
}

interface WorkflowDefinition {
  name: string;
  version: string;
  requires_plugins?: string[];
  steps: WorkflowStep[];
  [key: string]: unknown;
}

interface HookInput {
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  tool_output?: Record<string, unknown>;
  teammate_id?: string;
  session_id?: string;
  agent_id?: string;
  [key: string]: unknown; // Claude Code hook stdin is flexible
}

interface HookOutput {
  decision?: 'approve' | 'block';
  additionalContext?: string;
  hookEventName?: string;
  [key: string]: unknown;
}

interface SessionRegistry {
  [pluginName: string]: string; // plugin name → absolute plugin dir
}

interface GuardResult {
  decision: 'approve' | 'block';
  instruction?: string;
}
```

---

## §18. Invariants

- **I-1**: `engineInit` must be called before any other engine function. All engine functions access `STATE_FILE` and `WORKFLOW` globals.
- **I-2**: `stateWrite` always atomically writes via `atomicWrite` (write-to-tmp-then-mv).
- **I-3**: Every state mutation sets `updated_at` to current UTC ISO-8601 timestamp.
- **I-4**: `engineHandleHook` always returns a valid `HookOutput` JSON — never throws uncaught exceptions to Claude Code.
- **I-5**: `lock.ts` uses `mkdir` (not `flock`) for atomic fan-in — portable across Linux, macOS, Windows.
- **I-6**: `src/shared/` has zero imports from `src/lib/` or `src/hooks/` — enforced by TypeScript project references.
