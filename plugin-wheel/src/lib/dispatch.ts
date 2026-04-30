// FR-006/FR-003: Step dispatcher - routes to appropriate handler
import type { WorkflowStep, WheelState, TeammateEntry } from '../shared/state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import { stateSetStepStatus, stateSetStepOutput, stateSetAwaitingUserInput } from './state.js';
import { contextBuild } from './context.js';
import { resolveInputs } from './resolve_inputs.js';
import { guardCheck } from './guard.js';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

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

// FR-007: dispatchStep(step: WorkflowStep, hookType: HookType, hookInput: HookInput, stateFile: string, stepIndex: number): Promise<HookOutput>
export async function dispatchStep(
  step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  switch (step.type) {
    case 'agent':
      return dispatchAgent(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'command':
      return dispatchCommand(step, _hookType, _hookInput, stateFile, stepIndex);
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
      return dispatchBranch(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'loop':
      return dispatchLoop(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'parallel':
      return dispatchParallel(step, _hookType, _hookInput, stateFile, stepIndex);
    case 'approval':
      return dispatchApproval(step, _hookType, _hookInput, stateFile, stepIndex);
    default:
      return { decision: 'approve' };
  }
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
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
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

    // FR-008: Check for terminal step — set status to completed before archiving
    if ((step as any).terminal === true) {
      const state = await stateRead(stateFile);
      const updated = { ...state, status: 'completed' as const };
      await stateWrite(stateFile, updated);
    }

    return { decision: 'approve' };
  } catch (err) {
    const exitCode = (err as NodeJS.ErrnoException).code ?? 1;
    const timestamp = new Date().toISOString();
    await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command ?? '',
      exit_code: exitCode as number,
      timestamp,
    });
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    return { decision: 'approve' };
  }
}

// FR-014: dispatchWorkflow - handles type: "workflow" steps (child workflow activation)
async function dispatchWorkflow(
  step: WorkflowStep,
  hookType: HookType,
  _hookInput: HookInput,
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

    const engineModule = await import('./engine.js');
    try {
      await engineModule.engineKickstart(childStateFile);
    } catch (e) {
      // Non-fatal
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

// FR-026: dispatchTeamWait
async function dispatchTeamWait(
  _step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  const guardResult = await guardCheck(stateFile, stepIndex);
  if (guardResult.decision === 'block') {
    return {
      decision: 'block',
      additionalContext: guardResult.instruction,
    };
  }
  return { decision: 'approve' };
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
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
): Promise<HookOutput> {
  const stateModule = await import('./state.js');
  const state = await stateRead(stateFile);

  await stateSetStepStatus(stateFile, stepIndex, 'working');

  const condition = (step as any).condition;
  if (!condition) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
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
    await stateModule.stateSetCursor(stateFile, stepIndex + 1);
    return { decision: 'approve' };
  }

  const targetIndex = state.steps.findIndex((s: any) => s.id === targetId);
  if (targetIndex === -1) {
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
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

  await stateModule.stateSetCursor(stateFile, targetIndex);

  const timestamp = new Date().toISOString();
  await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
    command: `branch: condition='${condition}' exit=${condExit} target=${targetId}`,
    exit_code: condExit,
    timestamp,
  });

  return { decision: 'approve' };
}

// FR-025: dispatchLoop - evaluates condition, repeats or advances
async function dispatchLoop(
  step: WorkflowStep,
  _hookType: HookType,
  _hookInput: HookInput,
  stateFile: string,
  stepIndex: number
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
      await stateModule.stateSetCursor(stateFile, stepIndex + 1);
    } else {
      await stateSetStepStatus(stateFile, stepIndex, 'failed');
    }
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
      await stateModule.stateSetCursor(stateFile, stepIndex + 1);
      return { decision: 'approve' };
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
      await stateModule.stateSetCursor(stateFile, stepIndex + 1);
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