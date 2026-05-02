# Interface Contracts — Wheel TS Rewrite Parity Completion

Per Constitution Article VII: every signature here is the single source of truth. Implementation MUST match exactly. If a signature needs to change, this file MUST be updated FIRST.

All interfaces live in `plugin-wheel/src/lib/` unless otherwise noted. Many of these REUSE existing helpers (workflow.ts, state.ts, context.ts) rather than introducing new exports.

---

## 1. Existing helpers reused (no new export)

These are existing functions used by parity fixes. The implementer reads their current signature and uses them as-is. No contract change.

```typescript
// plugin-wheel/src/lib/workflow.ts (existing)
export function resolveNextIndex(step: WorkflowStep, stepIndex: number, workflow: WorkflowDef): number;
export function advancePastSkipped(stateFile: string, rawNext: number, workflow: WorkflowDef): Promise<number>;

// plugin-wheel/src/lib/state.ts (existing)
export async function stateClearAwaitingUserInput(stateFile: string, stepIndex: number): Promise<void>;
export async function stateRemoveTeam(stateFile: string, teamRef: string): Promise<void>;
export async function stateAddTeammate(stateFile: string, teamRef: string, teammate: TeammateEntry): Promise<void>;

// plugin-wheel/src/lib/context.ts (existing)
export async function contextCaptureOutput(stateFile: string, stepIndex: number, outputKey: string): Promise<void>;
export async function contextBuild(step: WorkflowStep, state: WheelState, resolvedInputs: Record<string, unknown>): Promise<string>;
```

If any of these is MISSING in current TS code, the implementer ports it from shell as a NEW export and updates this contract section before using. Specifically `stateRemoveTeam` and `contextCaptureOutput` are likely missing — verify at start of FR-006 / FR-002 work.

---

## 2. NEW: `contextWriteTeammateFiles` (FR-006 A2)

```typescript
// plugin-wheel/src/lib/context.ts (new export)
/**
 * FR-006 — write per-teammate context.md and assign_inputs.json into the
 * teammate's output_dir. Mirrors shell context_write_teammate_files.
 *
 * Side effects: creates outputDir if absent; writes two files:
 *   - <outputDir>/context.md         — rendered context block from contextFromJson
 *   - <outputDir>/assign_inputs.json — assignJson serialized
 *
 * Failure: throws on filesystem errors. Caller (dispatchTeammate) catches and
 * marks step failed.
 */
export async function contextWriteTeammateFiles(
  outputDir: string,
  state: WheelState,
  workflow: WorkflowDef,
  contextFromJson: unknown[],
  assignJson: Record<string, unknown>,
): Promise<void>;
```

Parity reference: `dispatch.sh:1806`, `dispatch.sh:1827`. Implementation port: shell `lib/context.sh` `context_write_teammate_files`.

---

## 3. NEW: `_chainParentAfterArchive` (FR-005 A1)

```typescript
// plugin-wheel/src/lib/dispatch.ts (new module-private helper, exported for tests)

/**
 * FR-005 — when a child workflow archives, advance the parent workflow's
 * cursor and dispatch the parent's next step. Mirrors shell
 * _chain_parent_after_archive (dispatch.sh:144).
 *
 * If parentSnap is empty / null / file missing: no-op, return approve.
 * Else: read parent state, resolve next index past current cursor,
 * dispatch the next step inline (cascade tail).
 */
export async function _chainParentAfterArchive(
  parentStateFile: string | null,
  hookType: HookType,
  hookInput: HookInput,
): Promise<HookOutput>;
```

Used by: `dispatchAgent` (FR-002 A5), `dispatchWorkflow` archive path (FR-005 A1), `dispatchTeammate` final step path. Hook into `archiveWorkflow` engine helper too.

---

## 4. NEW: `_teammateChainNext` + `_teammateFlushFromState` (FR-006 A3)

```typescript
// plugin-wheel/src/lib/dispatch.ts (module-private; exported for tests)

/**
 * FR-006 — after a teammate step marks done, look ahead at the next workflow
 * step:
 *  - if next step is also `teammate`: dispatch it directly (no block emitted).
 *  - if next step is NOT teammate (or end-of-workflow): flush all registered
 *    teammates from state into a SINGLE block message with batched spawn
 *    instructions for the orchestrator.
 *
 * Mirrors shell _teammate_chain_next (dispatch.sh:1889) and
 * _teammate_flush_from_state (dispatch.sh:1927).
 */
export async function _teammateChainNext(
  step: WorkflowStep,
  stepIndex: number,
  hookInput: HookInput,
  stateFile: string,
  teamRef: string,
  subWorkflow: string,
): Promise<HookOutput>;

/**
 * FR-006 — collect all teammates registered for `teamRef` and emit a block
 * message containing batched spawn instructions, one per teammate.
 */
async function _teammateFlushFromState(
  stateFile: string,
  teamRef: string,
  subWorkflow: string,
): Promise<HookOutput>;
```

Parity reference: `dispatch.sh:1889`, `dispatch.sh:1927`.

---

## 5. NEW: `_teamWaitComplete` (FR-006 A5, A6)

```typescript
// plugin-wheel/src/lib/dispatch.ts (module-private)

/**
 * FR-006 — finalise a `team-wait` step: collect all teammate outputs into
 * the wait step's output path as `summary.json`; if `collect_to` is set,
 * copy each teammate's output into the configured output_dir.
 *
 * Mirrors shell _team_wait_complete (dispatch.sh:2248).
 */
async function _teamWaitComplete(
  step: WorkflowStep,
  stateFile: string,
  stepIndex: number,
  teamRef: string,
): Promise<void>;
```

Called from `_recheckAndCompleteIfDone` (existing) when teammate count is fully done.

---

## 6. UPDATED: `dispatchTeamDelete` (FR-006 A7)

```typescript
// plugin-wheel/src/lib/dispatch.ts (replaces stub at line 902)

/**
 * FR-006 A7 — full implementation matching shell dispatch_team_delete
 * (dispatch.sh:2375). NOT a stub.
 *
 * Behaviour:
 *  - hookType === 'stop' AND step pending: if team already removed (idempotency),
 *    advance cursor + cascade. Else mark step working, emit block instructing
 *    orchestrator to call TeamDelete, including a force-message if any
 *    teammates are still running.
 *  - hookType === 'stop' AND step working: re-emit "still waiting for TeamDelete".
 *  - hookType === 'post_tool_use' AND step working AND tool_name === 'TeamDelete':
 *    state_remove_team; mark step done; handle terminal-step archive trigger;
 *    advance cursor; cascade into next auto-executable step.
 */
async function dispatchTeamDelete(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput>;
```

Implementation MUST call `stateRemoveTeam` (port from shell `state_remove_team` if missing in TS state.ts) and `handleTerminalStep` (existing TS engine helper / archive helper) before cursor advance.

---

## 7. UPDATED: `dispatchLoop` (FR-003)

Signature unchanged. Behaviour change scoped to:
- Line 1101: change `(reState.steps[stepIndex] as any)?.max_iterations ?? 10` to `(step as any).max_iterations ?? 10`. (Bug B fix.)
- Line 1109: replace `return { decision: 'approve' };` with recursive `return dispatchLoop(step, hookType, hookInput, stateFile, stepIndex, depth);`. (Bug A fix.)
- Line 1094 (substep command exec): pass `{ env: { ...process.env, WORKFLOW_PLUGIN_DIR: <derived> }, timeout: 300000 }`.

---

## 8. UPDATED: `dispatchAgent` (FR-002)

Signature unchanged. Behaviour changes:
- Line 237 area: before `stateSetStepStatus(stateFile, stepIndex, 'working')` for `pending` status, attempt `unlink(step.output)` if file exists. (FR-002 A1.)
- Line 261: replace `const newCursor = stepIndex + 1;` with `const rawNext = resolveNextIndex(step, stepIndex, workflow); const newCursor = await advancePastSkipped(stateFile, rawNext, workflow);`. (FR-002 A2.)
- Line 259: replace `stateSetStepOutput(stateFile, stepIndex, null)` with `await contextCaptureOutput(stateFile, stepIndex, outputKey)`. (FR-002 A4.)
- After `stateSetStepStatus(stateFile, stepIndex, 'done')`: add `await stateClearAwaitingUserInput(stateFile, stepIndex);`. (FR-002 A3.)
- After terminal-step archive trigger: call `await _chainParentAfterArchive(parentSnap, hookType, hookInput)`. (FR-002 A5.)
- Lines 251, 256, 262, 264, 267: DELETE all `console.error('DEBUG ...')` calls. (FR-002 A6.)

---

## 9. UPDATED: `dispatchCommand` (FR-001 A1)

Signature unchanged. Behaviour change:
- Line 320 (`execAsync(step.command, { timeout: 300000 })`): change to:

```typescript
const wfPluginDir = await deriveWorkflowPluginDir(stateFile);  // new helper, port shell logic
const { stdout, stderr } = await execAsync(step.command, {
  timeout: 300000,
  env: { ...process.env, ...(wfPluginDir ? { WORKFLOW_PLUGIN_DIR: wfPluginDir } : {}) },
});
```

```typescript
// plugin-wheel/src/lib/state.ts (or workflow.ts — implementer chooses)
/** FR-001 A1 — read state.workflow_file, return its 2-level dirname (the plugin dir). */
export async function deriveWorkflowPluginDir(stateFile: string): Promise<string | null>;
```

Parity reference: shell `dispatch.sh:1535–1544`.

---

## 10. UPDATED: `dispatchBranch` (FR-004 A1)

Signature unchanged. Behaviour change:
- Line 953 (`return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);`): change to use `resolveNextIndex(step, stepIndex, workflow) + advancePastSkipped`.

---

## 11. UPDATED: post-tool-use deactivate handler (FR-008 A1)

```typescript
// plugin-wheel/src/hooks/post-tool-use.ts

/**
 * FR-008 A1 — handle a `bin/deactivate.sh [<arg>]` invocation. Mirrors
 * shell post-tool-use.sh:81–176.
 *
 * Modes:
 *  - arg === '--all' → archive every state file in .wheel/state_*.json
 *  - arg non-empty → archive state files whose basename contains arg
 *  - arg empty → archive only the caller's own state file (matched by
 *    owner_session_id + owner_agent_id in the state file)
 *
 * After primary archive: cascade-stop child workflows (parent_workflow points
 * to a now-missing file) and team sub-workflows (teammates listed in the
 * archived state).
 *
 * Returns: HookOutput {hookEventName: 'PostToolUse'} always.
 */
async function handleDeactivate(
  command: string,
  hookInput: HookInput,
): Promise<HookOutput>;
```

---

## 12. Hygiene cleanup (no signature change)

Per FR-002 A6 + FR-008 A2: REMOVE every `console.error('DEBUG ...')` call across `dispatch.ts` + `post-tool-use.ts`. Final state: no `DEBUG ` prefix in either file. Auditor enforces via `git grep -F "DEBUG" plugin-wheel/src/{lib/dispatch.ts,hooks/post-tool-use.ts}` returning zero hits.

---

## 13. `package.json` change (FR-009)

```diff
   "devDependencies": {
-    "@vitest/coverage-v8": "^4.1.5",
+    "@vitest/coverage-v8": "^1.6.1",
     "vitest": "^1.6.1"
   }
```

If option (a) fails per `research.md §FR-009-decision`, fall back to:

```diff
   "devDependencies": {
-    "@vitest/coverage-v8": "^4.1.5",
+    "@vitest/coverage-v8": "^3.0.0",
-    "vitest": "^1.6.1"
+    "vitest": "^3.0.0"
   }
```

…and update this contract.

---

## Acceptance per Article VII

Every NEW or UPDATED signature listed here MUST appear with EXACTLY this shape in the implementation. Auditor verifies via `tsc --noEmit` plus signature grep. Any deviation is a contract violation and blocks PR creation.
