// FR-006/FR-003: Step dispatcher - routes to appropriate handler
import type { WorkflowStep, WheelState, TeammateEntry } from '../shared/state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import { stateSetStepStatus, stateSetStepOutput, stateSetAwaitingUserInput, stateList } from './state.js';
import { contextBuild } from './context.js';
import { resolveInputs } from './resolve_inputs.js';
import { wheelLog } from './log.js';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// FR-001 — single source of truth for cascade-eligible step types.
// Any per-dispatcher type duplication (e.g. `step.type === 'command'` style
// guards) inside cascade tails is a violation of FR-001's invariant. Keep
// this Set as the ONLY enumeration.
const AUTO_EXECUTABLE_STEP_TYPES: ReadonlySet<string> = new Set([
  'command',
  'loop',
  'branch',
]);

/**
 * FR-001 — classifier for cascade participation. True iff the step type is
 * in {'command','loop','branch'}. Cascade tails MUST call this rather than
 * inline-comparing step.type.
 */
export function isAutoExecutable(step: WorkflowStep | { type?: string }): boolean {
  return AUTO_EXECUTABLE_STEP_TYPES.has((step as any).type);
}

// FR-006 — hard cap on cascade recursion depth. Graceful halt at this depth.
export const CASCADE_DEPTH_CAP = 1000;

export type HookType = 'post_tool_use' | 'stop' | 'teammate_idle' | 'subagent_start' | 'subagent_stop' | 'session_start';

export interface HookInput {
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  tool_output?: Record<string, unknown>;
  teammate_id?: string;
  session_id?: string;
  agent_id?: string;
  agent_type?: string;
  [key: string]: unknown;
}

export interface HookOutput {
  decision?: 'approve' | 'block';
  additionalContext?: string;
  hookEventName?: string;
  [key: string]: unknown;
}

// FR-007: dispatchStep(step, hookType, hookInput, stateFile, stepIndex, depth?)
// FR-006: depth tracks cascade recursion; external callers omit (defaults 0).
export async function dispatchStep(
  step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0
): Promise<HookOutput> {
  switch (step.type) {
    case 'agent':
      return dispatchAgent(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'command':
      // FR-002 — cascade-emitting dispatcher; depth threaded.
      return dispatchCommand(step, _hookType, _hookInput, stateFile, stepIndex, depth);
    case 'workflow':
      return dispatchWorkflow(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'team-create':
      return dispatchTeamCreate(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'teammate':
      return dispatchTeammate(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'team-wait':
      return dispatchTeamWait(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'team-delete':
      return dispatchTeamDelete(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'branch':
      // FR-004 — cascade-emitting dispatcher; depth threaded.
      return dispatchBranch(step, _hookType, _hookInput, stateFile, stepIndex, depth);
    case 'loop':
      // FR-003 — cascade-emitting dispatcher; depth threaded.
      return dispatchLoop(step, _hookType, _hookInput, stateFile, stepIndex, depth);
    case 'parallel':
      return dispatchParallel(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'approval':
      return dispatchApproval(step, _hookType, _hookInput, stateFile, stepIndex);
    default:
      return { decision: 'approve' };
  }
}

/**
 * FR-002/FR-003/FR-004/FR-006/FR-008/FR-009 — shared cascade tail.
 * Module-private; reachable only from cascade-emitting dispatchers.
 *
 * Contract:
 *   1. Read fresh state.
 *   2. nextIndex >= steps.length → advance cursor, log end_of_workflow halt.
 *   3. Advance cursor to nextIndex FIRST (idempotency: a mid-dispatch crash
 *      leaves state at the right cursor, next hook fire retries the right step).
 *   4. depth >= cap → log depth_cap halt, return.
 *   5. !isAutoExecutable(nextStep) → log blocking_step halt, return.
 *   6. Log dispatch_cascade hop, recurse with depth+1.
 */
async function cascadeNext(
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  nextIndex: number,
  depth: number
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  let state;
  try {
    state = await stateRead(stateFile);
  } catch {
    // State file gone (race with archive) — bail.
    return { decision: 'approve' };
  }

  const fromCursor = state.cursor;
  const fromStep: any = state.steps[fromCursor] ?? {};
  const fromStepId = fromStep.id ?? '';
  const fromStepType = fromStep.type ?? '';

  // FR-009 — end-of-workflow halt.
  if (nextIndex >= state.steps.length) {
    await stateModule.stateSetCursor(stateFile, nextIndex);
    await wheelLog('cursor_advance', {
      from_cursor: fromCursor,
      to_cursor: nextIndex,
      state_file: stateFile,
    });
    await wheelLog('dispatch_cascade_halt', {
      step_id: fromStepId,
      step_type: fromStepType,
      reason: 'end_of_workflow',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // FR-004 — walk past 'skipped' steps (e.g., off-target branch arms)
  // so cascade doesn't re-execute them. Mirrors maybeAdvanceParentTeamWaitCursor.
  let resolvedIndex = nextIndex;
  while (
    resolvedIndex < state.steps.length &&
    state.steps[resolvedIndex]?.status === 'skipped'
  ) {
    resolvedIndex++;
  }
  if (resolvedIndex >= state.steps.length) {
    await stateModule.stateSetCursor(stateFile, resolvedIndex);
    await wheelLog('cursor_advance', {
      from_cursor: fromCursor, to_cursor: resolvedIndex, state_file: stateFile,
    });
    await wheelLog('dispatch_cascade_halt', {
      step_id: fromStepId, step_type: fromStepType,
      reason: 'end_of_workflow', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // Prefer workflow_definition.steps (full WorkflowStep with command,
  // condition, substep, etc.) over state.steps (projection that strips
  // command/condition fields). dispatchCommand short-circuits when
  // step.command is missing — without this, cascade silently no-ops on
  // every hop.
  const wfDef = (state as any).workflow_definition;
  const wfSteps: any[] = wfDef?.steps ?? state.steps;
  const nextStep: any = wfSteps[resolvedIndex] ?? state.steps[resolvedIndex];

  // FR-008 — advance cursor BEFORE recursing (idempotency contract).
  await stateModule.stateSetCursor(stateFile, resolvedIndex);
  await wheelLog('cursor_advance', {
    from_cursor: fromCursor,
    to_cursor: resolvedIndex,
    state_file: stateFile,
  });

  // FR-006 — depth cap halt.
  if (depth >= CASCADE_DEPTH_CAP) {
    await wheelLog('dispatch_cascade_halt', {
      step_id: nextStep.id ?? '',
      step_type: nextStep.type ?? '',
      reason: 'depth_cap',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // FR-001 — single classifier; FR-009 — blocking-step halt log.
  if (!isAutoExecutable(nextStep)) {
    await wheelLog('dispatch_cascade_halt', {
      step_id: nextStep.id ?? '',
      step_type: nextStep.type ?? '',
      reason: 'blocking_step',
      state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  // FR-009 — cascade hop log.
  await wheelLog('dispatch_cascade', {
    from_step_id: fromStepId,
    from_step_type: fromStepType,
    to_step_id: nextStep.id ?? '',
    to_step_type: nextStep.type ?? '',
    hook_type: hookType,
    state_file: stateFile,
  });

  // FR-007 — pass hookType through unchanged. FR-006 — depth + 1.
  return dispatchStep(nextStep as WorkflowStep, hookType, hookInput, stateFile, resolvedIndex, depth + 1);
}

// FR-003: dispatchAgent - handles type: "agent" steps
async function dispatchAgent(
  step: WorkflowStep,
  hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  if (hookType !== 'stop' && hookType !== 'post_tool_use') {
    return { decision: 'approve' };
  }

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');

      // Build context for agent
      const resolvedInputs = step.inputs ? resolveInputs(step.inputs, {} as WheelState, {} as any, {}) : {};
      const context = await contextBuild(step, {} as WheelState, resolvedInputs);

      return {
        decision: 'block',
        additionalContext: context,
      };
    } else if (stepStatus === 'working') {
      // Check if the agent completed its work (output file exists)
      const outputKey = (step as any).output as string | undefined;
      console.error('DEBUG dispatchAgent: stop hook, step working, outputKey=', outputKey);
      if (outputKey) {
        try {
          const { access } = await import('fs/promises');
          await access(outputKey);
          console.error('DEBUG dispatchAgent: output file EXISTS, marking done');
          // Output file exists — agent completed, mark done
          const stateModule = await import('./state.js');
          await stateSetStepOutput(stateFile, stepIndex, null);
          await stateSetStepStatus(stateFile, stepIndex, 'done');
          const newCursor = stepIndex + 1;
          console.error('DEBUG dispatchAgent: calling stateSetCursor with', newCursor);
          await (stateModule as any).stateSetCursor(stateFile, newCursor);
          console.error('DEBUG dispatchAgent: done, returning approve');
          return { decision: 'approve' };
        } catch (e) {
          console.error('DEBUG dispatchAgent: output file not yet present:', e);
          // Output file not yet present, still waiting
        }
      }
      return {
        decision: 'block',
        additionalContext: 'Still waiting for agent step to complete...',
      };
    }
  }

  if (hookType === 'post_tool_use') {
    // On re-entry (step already working), just approve — stale output cleanup
    // is handled by the stop hook (shell hook). Don't re-check output file here.
    if (stepStatus === 'working') {
      return { decision: 'approve' };
    }

    await stateSetStepStatus(stateFile, stepIndex, 'working');

    // Build context for agent
    const resolvedInputs = step.inputs ? resolveInputs(step.inputs, {} as WheelState, {} as any, {}) : {};
    const context = await contextBuild(step, {} as WheelState, resolvedInputs);

    return {
      decision: 'approve',
      additionalContext: context,
    };
  }

  return { decision: 'approve' };
}

// FR-019: dispatchCommand - executes command steps inline
// Note: hookType is accepted but ignored. dispatchCommand always executes (hook
// type routing is done in dispatchStep/handleNormalPath). This differs from
// dispatchAgent which gates on hookType because agent blocks need 'stop' hook.
async function dispatchCommand(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0  // FR-002 / FR-006 — cascade depth threaded.
): Promise<HookOutput> {
  if (!step.command) {
    return { decision: 'approve' };
  }

  const stateModule = await import('./state.js');
  await stateSetStepStatus(stateFile, stepIndex, 'working');

  try {
    const { stdout, stderr } = await execAsync(step.command, { timeout: 300000 });
    const timestamp = new Date().toISOString();
    await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command,
      exit_code: 0,
      timestamp,
    });

    await stateSetStepOutput(stateFile, stepIndex, stdout || stderr);
    await stateSetStepStatus(stateFile, stepIndex, 'done');

    // FR-008: Check for terminal step — set status to completed (no cascade after terminal).
    if ((step as any).terminal === true) {
      const state = await stateRead(stateFile);
      const updated = { ...state, status: 'completed' as const };
      await stateWrite(stateFile, updated);
      await wheelLog('dispatch_cascade_halt', {
        step_id: step.id, step_type: step.type,
        reason: 'terminal', state_file: stateFile,
      });
      return { decision: 'approve' };
    }

    // FR-002 — cascade to next step after success.
    return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
  } catch (err) {
    const exitCode = (err as NodeJS.ErrnoException).code ?? 1;
    const timestamp = new Date().toISOString();
    await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command ?? '',
      exit_code: exitCode as number,
      timestamp,
    });
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    // FR-008 — cascade halts on failure. Set state.status='failed' so the
    // activation-path archive logic (maybeArchiveAfterActivation) detects
    // terminal-on-failure and routes the workflow to history/failure/.
    {
      const fresh = await stateRead(stateFile);
      await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    }
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }
}

// FR-014: dispatchWorkflow - handles type: "workflow" steps (child workflow activation)
// FR-001 Composite / US-5 (wheel-ts-dispatcher-cascade): the parent's
// cascade pauses on this step type (cascadeNext halts at !isAutoExecutable).
// When the parent later dispatches the workflow step itself, we activate
// the child AND kick off the child's first step in the child's state so
// its cascade runs back-to-back inside this same hook fire — matching the
// shell wheel's dispatch_step recursion. Parent then returns block; child
// resume is handled via the existing wait-all archive path (out of scope
// for this PRD).
async function dispatchWorkflow(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  if (hookType !== 'stop' && hookType !== 'post_tool_use') {
    return { decision: 'approve' };
  }

  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (stepStatus === 'pending') {
    await stateSetStepStatus(stateFile, stepIndex, 'working');

    const childName = (step as any).workflow;
    if (!childName) {
      return { decision: 'approve' };
    }

    const safeChildName = childName.replace(/\//g, '-');
    const childUnique = `child_${safeChildName}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const childStateFile = `.wheel/state_${childUnique}.json`;

    const workflowModule = await import('./workflow.js');
    let childFile = `workflows/${childName}.json`;
    if (childName.includes(':')) {
      childFile = `workflows/${childName.split(':')[1]}.json`;
    }

    let childJson: any;
    try {
      childJson = await workflowModule.workflowLoad(childFile);
    } catch (e) {
      await stateSetStepStatus(stateFile, stepIndex, 'failed');
      return { decision: 'approve' };
    }

    await stateModule.stateInit({
      stateFile: childStateFile,
      workflow: childJson,
      sessionId: state.owner_session_id ?? '',
      agentId: state.owner_agent_id ?? '',
    });

    // Persist child workflow_definition so subsequent hooks can resolve it
    // via stateRead (matches handleActivation's pattern).
    try {
      const persistedChild = await stateRead(childStateFile);
      (persistedChild as any).workflow_definition = childJson;
      await stateWrite(childStateFile, persistedChild);
    } catch {
      // non-fatal
    }

    const engineModule = await import('./engine.js');
    try {
      await engineModule.engineKickstart(childStateFile);
    } catch (e) {
      // Non-fatal
    }

    // FR-001 Composite / US-5 — child cascade kicked off in child state.
    // dispatchStep recurses through the cascade tails (FR-002/003/004).
    const childSteps = childJson.steps ?? [];
    if (childSteps.length > 0 && isAutoExecutable(childSteps[0])) {
      try {
        await dispatchStep(childSteps[0] as WorkflowStep, 'post_tool_use', hookInput, childStateFile, 0, 0);
      } catch (err) {
        console.error('DEBUG: dispatchWorkflow child cascade error:', err);
      }
      // Mirror handleActivation: archive child if cascade drove it terminal.
      try {
        const engineMod = await import('./engine.js');
        await engineMod.maybeArchiveAfterActivation(childStateFile);
      } catch {
        // non-fatal
      }
    }

    return {
      decision: 'block',
      additionalContext: `Child workflow activated: ${childName}`,
    };
  } else if (stepStatus === 'working') {
    const childName = (step as any).workflow ?? 'unknown';
    return {
      decision: 'block',
      additionalContext: `Waiting for child workflow to complete: ${childName}`,
    };
  }

  return { decision: 'approve' };
}

// FR-025: dispatchTeamCreate - creates a Claude Code agent team
async function dispatchTeamCreate(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';
  const stepId = step.id;
  const teamName = (step as any).team_name ?? `${state.workflow_name}-${stepId}`;

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      const existingTeam = (state as any).teams?.[stepId]?.team_name;
      if (existingTeam) {
        await stateSetStepStatus(stateFile, stepIndex, 'done');
        return { decision: 'approve' };
      }
      await stateSetStepStatus(stateFile, stepIndex, 'working');
      return {
        decision: 'block',
        additionalContext: `Create an agent team by calling TeamCreate with team_name: ${teamName}. After creating, proceed with the next tool call so I can detect completion.`,
      };
    } else if (stepStatus === 'working') {
      return {
        decision: 'block',
        additionalContext: `Still waiting for TeamCreate to be called for team: ${teamName}. Call TeamCreate now.`,
      };
    }
    return { decision: 'approve' };
  } else if (hookType === 'post_tool_use') {
    if (stepStatus === 'working') {
      const toolName = hookInput.tool_name;
      if (toolName === 'TeamCreate') {
        await stateModule.stateSetTeam(stateFile, stepId, teamName);
        await stateSetStepStatus(stateFile, stepIndex, 'done');
      }
    }
    return { decision: 'approve' };
  }

  return { decision: 'approve' };
}

// FR-025/FR-026: dispatchTeammate - spawn agent(s) to run sub-workflows
async function dispatchTeammate(
  step: WorkflowStep,
  hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  if (hookType !== 'stop') {
    return { decision: 'approve' };
  }

  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (stepStatus === 'pending') {
    await stateSetStepStatus(stateFile, stepIndex, 'working');

    const teamRef = (step as any).team;
    const subWorkflow = (step as any).workflow;
    const loopFrom = (step as any).loop_from;
    const maxAgents = (step as any).max_agents ?? 5;
    const agentName = (step as any).name ?? step.id;

    const teamName = state.teams?.[teamRef]?.team_name;
    if (!teamName) {
      await stateSetStepStatus(stateFile, stepIndex, 'failed');
      return { decision: 'approve' };
    }

    if (loopFrom) {
      const loopStepIndex = state.steps.findIndex((s: any) => s.id === loopFrom);
      if (loopStepIndex === -1) {
        await stateSetStepStatus(stateFile, stepIndex, 'failed');
        return { decision: 'approve' };
      }

      const loopOutput = state.steps[loopStepIndex]?.output as string | null;
      if (!loopOutput) {
        await stateSetStepStatus(stateFile, stepIndex, 'failed');
        return { decision: 'approve' };
      }

      let items: any[] = [];
      try {
        const { readFile } = await import('fs/promises');
        const content = await readFile(loopOutput, 'utf-8');
        items = JSON.parse(content);
      } catch (e) {
        await stateSetStepStatus(stateFile, stepIndex, 'failed');
        return { decision: 'approve' };
      }

      if (!Array.isArray(items)) {
        await stateSetStepStatus(stateFile, stepIndex, 'failed');
        return { decision: 'approve' };
      }

      if (items.length === 0) {
        await stateSetStepStatus(stateFile, stepIndex, 'done');
        return { decision: 'approve' };
      }

      const agentCount = Math.min(items.length, maxAgents);

      for (let i = 0; i < agentCount; i++) {
        const name = `${agentName}-${i}`;
        const teammate: TeammateEntry = {
          task_id: '',
          status: 'pending',
          agent_id: name,
          output_dir: `.wheel/outputs/team-${teamName}/${name}`,
          assign: {},
          started_at: null,
          completed_at: null,
        };
        await stateModule.stateAddTeammate(stateFile, teamRef, teammate);
      }

      await stateSetStepStatus(stateFile, stepIndex, 'done');
      return {
        decision: 'block',
        additionalContext: `Spawned ${agentCount} agents for ${subWorkflow}`,
      };
    } else {
      const teammate: TeammateEntry = {
        task_id: '',
        status: 'pending',
        agent_id: agentName,
        output_dir: `.wheel/outputs/team-${teamName}/${agentName}`,
        assign: (step as any).assign ?? {},
        started_at: null,
        completed_at: null,
      };
      await stateModule.stateAddTeammate(stateFile, teamRef, teammate);

      await stateSetStepStatus(stateFile, stepIndex, 'done');
      return {
        decision: 'block',
        additionalContext: `Spawned agent: ${agentName} for ${subWorkflow}`,
      };
    }
  }

  return { decision: 'approve' };
}

// FR-003 (wheel-wait-all-redesign): pure re-check helper. Counts teammate
// statuses; if all are 'completed' or 'failed' (and at least one teammate
// exists), marks the parent's `team-wait` step done. Otherwise no-op.
// Does NOT mutate teammate slot status — those mutations come from FR-001
// (archive helper) and FR-004 (polling backstop).
async function _recheckAndCompleteIfDone(
  stateFile: string,
  stepIndex: number,
  teamRef: string
): Promise<boolean> {
  const state = await stateRead(stateFile);
  const team = state.teams?.[teamRef];
  if (!team) return false;
  const teammates = team.teammates ?? {};
  const names = Object.keys(teammates);

  // Edge case: 0 teammates — mark done immediately (matches dispatchTeammate's
  // 0-items short-circuit and preserves backwards behavior of the old function).
  if (names.length === 0) {
    if (state.steps[stepIndex]?.status !== 'done') {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
    }
    return true;
  }

  for (const name of names) {
    const status = teammates[name]?.status ?? 'pending';
    if (status !== 'completed' && status !== 'failed') {
      return false;
    }
  }

  if (state.steps[stepIndex]?.status !== 'done') {
    await stateSetStepStatus(stateFile, stepIndex, 'done');
  }
  return true;
}

// FR-003 (wheel-wait-all-redesign): two-branch state-driven dispatcher.
// Does NOT mutate teammate slot status. The cross-process signal arrives
// via FR-001 (archive helper writes parent slot under parent's flock) or
// FR-004 (polling backstop reconciles orphans). teammate_idle and
// subagent_stop hook events are remapped to 'post_tool_use' upstream by
// FR-005 hook routing in engine.ts.
async function dispatchTeamWait(
  step: WorkflowStep,
  hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  const stepId = step.id;
  const teamRef = (step as { team?: string }).team ?? stepId;

  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  // FR-003: stop branch — pending→working transition + re-check.
  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');
    }
    const done = await _recheckAndCompleteIfDone(stateFile, stepIndex, teamRef);
    if (done) {
      return { decision: 'approve' };
    }
    // Not done — return approve so the parent harness goes idle waiting
    // for the next archive write to advance the slot. Block-with-context
    // is unnecessary here: the archive helper (FR-001) writes under the
    // parent's lock and the cursor advance happens there directly.
    return { decision: 'approve' };
  }

  // FR-003 + FR-004: post_tool_use branch — polling backstop first
  // (reconciles orphans by reading live state files + history buckets),
  // then re-check.
  if (hookType === 'post_tool_use') {
    if (stepStatus !== 'working' && stepStatus !== 'pending') {
      return { decision: 'approve' };
    }
    // FR-004: run polling backstop BEFORE the re-check so any reconciled
    // orphans are visible to _recheckAndCompleteIfDone in the same call.
    await _runPollingBackstop(stateFile, teamRef);
    await _recheckAndCompleteIfDone(stateFile, stepIndex, teamRef);
    return { decision: 'approve' };
  }

  return { decision: 'approve' };
}

// FR-004 (wheel-wait-all-redesign): polling backstop. For each teammate
// currently status=='running' in parent.teams[teamRef].teammates,
// reconcile against live state files → history buckets → orphan default.
// Persists all mutations under a single parent-flock acquisition (one
// write at the end of the sweep). Cost target: one .wheel/ readdir + up
// to three history bucket reads per invocation, regardless of teammate
// count.
async function _runPollingBackstop(
  parentStateFile: string,
  teamRef: string
): Promise<{ reconciledCount: number; stillRunningCount: number }> {
  const { withLockBlocking } = await import('./lock.js');
  const { wheelLog } = await import('./log.js');
  const { promises: fs } = await import('fs');
  const path = (await import('path')).default;

  // Snapshot the running teammates outside the lock; this is a hot read
  // path and we don't want to hold the parent lock during disk scans.
  let preState: Awaited<ReturnType<typeof stateRead>>;
  try {
    preState = await stateRead(parentStateFile);
  } catch {
    return { reconciledCount: 0, stillRunningCount: 0 };
  }
  const team = preState.teams?.[teamRef];
  if (!team) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile,
      team_id: teamRef,
      reconciled_count: 0,
      still_running_count: 0,
      note: 'team_not_found',
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }
  const teammates = team.teammates ?? {};
  const runningSlots = Object.entries(teammates).filter(
    ([, slot]) => slot?.status === 'running'
  );
  if (runningSlots.length === 0) {
    await wheelLog('wait_all_polling', {
      parent_state_file: parentStateFile,
      team_id: teamRef,
      reconciled_count: 0,
      still_running_count: 0,
    });
    return { reconciledCount: 0, stillRunningCount: 0 };
  }

  // Build live alternate_agent_id set. stateList scans .wheel/state_*.json.
  const liveAgentIds = new Set<string>();
  try {
    const liveFiles = await stateList();
    for (const sf of liveFiles) {
      try {
        const ss = await stateRead(sf);
        const aid = (ss as { alternate_agent_id?: string }).alternate_agent_id;
        if (aid) liveAgentIds.add(aid);
      } catch {
        // ignore unreadable state files
      }
    }
  } catch {
    // .wheel may not exist
  }

  // Build history bucket → set of (parent_state_file, alternate_agent_id) pairs.
  // Buckets are read once per sweep regardless of how many teammates need
  // reconciliation (cost target).
  const buckets: Array<{ name: 'success' | 'failure' | 'stopped'; status: 'completed' | 'failed' }> = [
    { name: 'success', status: 'completed' },
    { name: 'failure', status: 'failed' },
    { name: 'stopped', status: 'failed' },
  ];
  const bucketArchives: Record<string, Map<string, 'completed' | 'failed'>> = {};
  for (const b of buckets) {
    const dir = path.join('.wheel', 'history', b.name);
    const map = new Map<string, 'completed' | 'failed'>();
    try {
      const entries = await fs.readdir(dir);
      for (const entry of entries) {
        if (!entry.endsWith('.json')) continue;
        const fp = path.join(dir, entry);
        try {
          const content = await fs.readFile(fp, 'utf-8');
          const archived = JSON.parse(content) as {
            parent_workflow?: string | null;
            alternate_agent_id?: string;
          };
          if (
            archived.parent_workflow === parentStateFile &&
            archived.alternate_agent_id
          ) {
            // Archive evidence wins — first hit per agent_id stays.
            if (!map.has(archived.alternate_agent_id)) {
              map.set(archived.alternate_agent_id, b.status);
            }
          }
        } catch {
          // skip unreadable archive
        }
      }
    } catch {
      // bucket may not exist yet
    }
    bucketArchives[b.name] = map;
  }

  // Resolve each running teammate. Order MUST be live → history → orphan.
  type Resolution = {
    name: string;
    newStatus: 'completed' | 'failed';
    failureReason?: string;
  };
  const resolutions: Resolution[] = [];
  let stillRunning = 0;
  for (const [name, slot] of runningSlots) {
    const aid = slot?.agent_id ?? '';
    if (aid && liveAgentIds.has(aid)) {
      stillRunning++;
      continue;
    }
    let resolved: 'completed' | 'failed' | null = null;
    // FR-004 strict order: success first, then failure, then stopped.
    if (bucketArchives.success.has(aid)) {
      resolved = bucketArchives.success.get(aid)!;
    } else if (bucketArchives.failure.has(aid)) {
      resolved = bucketArchives.failure.get(aid)!;
    } else if (bucketArchives.stopped.has(aid)) {
      resolved = bucketArchives.stopped.get(aid)!;
    }

    if (resolved !== null) {
      resolutions.push({ name, newStatus: resolved });
    } else {
      // Orphan: state file disappeared without archiving.
      resolutions.push({
        name,
        newStatus: 'failed',
        failureReason: 'state-file-disappeared',
      });
    }
  }

  let reconciled = 0;
  if (resolutions.length > 0) {
    // FR-007: take parent lock for the single write.
    await withLockBlocking(parentStateFile, async () => {
      const parent = await stateRead(parentStateFile);
      const team2 = parent.teams?.[teamRef];
      if (!team2) return;
      const t2 = team2.teammates ?? {};
      const now = new Date().toISOString();
      for (const r of resolutions) {
        const slot = t2[r.name];
        if (!slot) continue;
        // Re-check status in case archive helper raced ahead.
        if (slot.status === 'completed' || slot.status === 'failed') continue;
        slot.status = r.newStatus;
        slot.completed_at = now;
        if (r.failureReason) {
          slot.failure_reason = r.failureReason;
        }
        reconciled++;
      }
      parent.updated_at = now;
      await stateWrite(parentStateFile, parent);
    });
  }

  await wheelLog('wait_all_polling', {
    parent_state_file: parentStateFile,
    team_id: teamRef,
    reconciled_count: reconciled,
    still_running_count: stillRunning,
  });

  return { reconciledCount: reconciled, stillRunningCount: stillRunning };
}

// FR-025: dispatchTeamDelete
async function dispatchTeamDelete(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  _stateFile: string,
  _stepIndex: number
): Promise<HookOutput> {
  return { decision: 'approve' };
}

// FR-024: dispatchBranch - evaluates condition, jumps to target
async function dispatchBranch(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0  // FR-004 / FR-006 — cascade depth threaded.
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);

  await stateSetStepStatus(stateFile, stepIndex, 'working');

  const condition = (step as any).condition;
  if (!condition) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    // FR-008 — cascade halts on failure; mark workflow terminal-failed.
    {
      const fresh = await stateRead(stateFile);
      await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    }
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  let condExit = 0;
  try {
    await execAsync(`eval "${condition}"`);
  } catch (e: any) {
    condExit = e.code ?? 1;
  }

  const targetId = condExit === 0 ? (step as any).if_zero : (step as any).if_nonzero;

  if (!targetId || targetId === 'END') {
    await stateSetStepStatus(stateFile, stepIndex, 'done');
    // FR-004 — branch with no target falls through to next step.
    return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
  }

  const targetIndex = state.steps.findIndex((s: any) => s.id === targetId);
  if (targetIndex === -1) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    // FR-008 — cascade halts on failure; mark workflow terminal-failed.
    {
      const fresh = await stateRead(stateFile);
      await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    }
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  await stateSetStepStatus(stateFile, stepIndex, 'done');

  const otherTargetId = condExit === 0 ? (step as any).if_nonzero : (step as any).if_zero;
  if (otherTargetId) {
    const otherIndex = state.steps.findIndex((s: any) => s.id === otherTargetId);
    if (otherIndex !== -1) {
      await stateSetStepStatus(stateFile, otherIndex, 'skipped');
    }
  }

  const timestamp = new Date().toISOString();
  await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
    command: `branch: condition='${condition}' exit=${condExit} target=${targetId}`,
    exit_code: condExit,
    timestamp,
  });

  // FR-004 — cascade to branch target. cascadeNext sets cursor to targetIndex.
  return cascadeNext(hookType, hookInput, stateFile, targetIndex, depth);
}

// FR-025: dispatchLoop - evaluates condition, repeats or advances
async function dispatchLoop(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0  // FR-003 / FR-006 — cascade depth threaded.
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (stepStatus === 'pending') {
    await stateSetStepStatus(stateFile, stepIndex, 'working');
  }

  const maxIterations = (step as any).max_iterations ?? 10;
  const onExhaustion = (step as any).on_exhaustion ?? 'fail';
  const condition = (step as any).condition;

  const currentIteration = (state.steps[stepIndex] as any)?.loop_iteration ?? 0;

  if (currentIteration >= maxIterations) {
    const timestamp = new Date().toISOString();
    await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
      command: `loop: exhausted after ${currentIteration} iterations`,
      exit_code: 1,
      timestamp,
    });

    if (onExhaustion === 'continue') {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      // FR-003 — cascade after loop exhausted.
      return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
    }
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    // FR-008 — cascade halts on failure; mark workflow terminal-failed.
    {
      const fresh = await stateRead(stateFile);
      await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    }
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }

  if (condition) {
    let condExit = 0;
    try {
      await execAsync(`eval "${condition}"`);
    } catch (e: any) {
      condExit = e.code ?? 1;
    }

    if (condExit === 0) {
      const timestamp = new Date().toISOString();
      await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
        command: `loop: condition met at iteration ${currentIteration}`,
        exit_code: 0,
        timestamp,
      });
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      // FR-003 — cascade after loop condition met early.
      return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
    }
  }

  // Increment iteration counter
  const newState = { ...state };
  if (!newState.steps[stepIndex]) {
    newState.steps[stepIndex] = {
      id: '',
      type: '',
      status: 'pending',
      started_at: null,
      completed_at: null,
      output: null,
      command_log: [],
      agents: {},
      loop_iteration: 0,
      awaiting_user_input: false,
      awaiting_user_input_since: null,
      awaiting_user_input_reason: null,
      resolved_inputs: null,
      contract_emitted: false,
    };
  }
  (newState.steps[stepIndex] as any).loop_iteration = currentIteration + 1;
  await stateWrite(stateFile, newState);

  const substep = (step as any).substep;
  if (!substep) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }

  const substepType = substep.type;
  if (substepType === 'command') {
    try {
      await execAsync(substep.command, { timeout: 300000 });
    } catch (e: any) {
      // Continue loop even on command failure
    }

    const reState = await stateRead(stateFile);
    const reIteration = (reState.steps[stepIndex] as any)?.loop_iteration ?? 0;
    const reMaxIter = (reState.steps[stepIndex] as any)?.max_iterations ?? 10;

    if (reIteration >= reMaxIter) {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      // FR-003 — cascade after final loop iteration completes.
      return cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
    }

    return { decision: 'approve' };
  } else if (substepType === 'agent') {
    const instruction = substep.instruction ?? '';
    return {
      decision: 'block',
      additionalContext: `Loop iteration ${currentIteration + 1}/${maxIterations}: ${instruction}`,
    };
  }

  return { decision: 'approve' };
}

// FR-009: dispatchParallel - fan-out agent instructions
async function dispatchParallel(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (hookType === 'stop') {
    if (stepStatus === 'pending') {
      await stateSetStepStatus(stateFile, stepIndex, 'working');

      const agents = (step as any).agents ?? [];
      for (const agent of agents) {
        await stateModule.stateSetAgentStatus(stateFile, stepIndex, agent, 'pending');
      }
    }

    const instruction = (step as any).instruction ?? 'Spawn parallel agents for this step.';
    const agentList = ((step as any).agents ?? []).join(', ');
    return {
      decision: 'block',
      additionalContext: `Spawn these agents in parallel: ${agentList}. ${instruction}`,
    };
  } else if (hookType === 'teammate_idle') {
    const agentType = hookInput.agent_type;
    if (!agentType) return { decision: 'approve' };

    const agentStatus = state.steps[stepIndex]?.agents?.[agentType]?.status;
    if (agentStatus === 'pending' || agentStatus === 'idle') {
      await stateModule.stateSetAgentStatus(stateFile, stepIndex, agentType, 'working');
      const agentInstructions = (step as any).agent_instructions ?? {};
      const agentInstruction = agentInstructions[agentType] ?? (step as any).instruction ?? '';
      return {
        decision: 'block',
        additionalContext: agentInstruction,
      };
    }
    return { decision: 'approve' };
  } else if (hookType === 'subagent_stop') {
    const agentType = hookInput.agent_type;
    if (agentType) {
      await stateModule.stateSetAgentStatus(stateFile, stepIndex, agentType, 'done');
    }

    const updatedState = await stateRead(stateFile);
    const agents = updatedState.steps[stepIndex]?.agents ?? {};
    const allDone = Object.values(agents).every((a: any) => a.status === 'done');

    if (allDone) {
      await stateSetStepStatus(stateFile, stepIndex, 'done');
      await stateModule.stateSetCursor(stateFile, stepIndex + 1);
    }

    return { decision: 'approve' };
  }

  return { decision: 'approve' };
}

// FR-013: dispatchApproval - blocks orchestrator
async function dispatchApproval(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  await stateSetAwaitingUserInput(stateFile, stepIndex, 'Approval required');
  return {
    decision: 'block',
    additionalContext: 'Approval required for this step. Please review and approve.',
  };
}

// FR-G3-1/FR-G3-4: _hydrateAgentStep - resolves step inputs against state + workflow + registry
export async function _hydrateAgentStep(
  step: WorkflowStep,
  _state: WheelState,
  _workflow: any,
  _stateFile: string,
  _stepIndex: number
): Promise<string> {
  if (!step.inputs) return '{}';

  try {
    const resolved = resolveInputs(step.inputs, _state, _workflow, {});
    return JSON.stringify(resolved);
  } catch (err) {
    return JSON.stringify({ error: String(err) });
  }
}