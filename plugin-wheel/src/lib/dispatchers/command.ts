// dispatchCommand — handles `type: "command"` steps.
//
// Note: hookType is accepted but ignored. dispatchCommand always executes
// (hook routing is done by dispatchStep / handleNormalPath upstream).
// This differs from dispatchAgent which gates on hookType.
//
// Lifecycle: pending → working → execAsync(step.command) → done | failed.
// Cascades to next step on success; halts cascade on failure or terminal.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead, stateWrite } from '../../shared/state.js';
import { stateSetStepStatus, stateSetStepOutput } from '../state.js';
import { wheelLog } from '../log.js';
import { exec } from 'child_process';
import { promisify } from 'util';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

const execAsync = promisify(exec);

export async function dispatchCommand(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
  depth: number = 0,
): Promise<HookOutput> {
  if (!step.command) return { decision: 'approve' };

  const stateModule = await import('../state.js');
  await stateSetStepStatus(stateFile, stepIndex, 'working');

  // parity: shell dispatch.sh:1535–1544 — export WORKFLOW_PLUGIN_DIR for plugin-shipped commands.
  const wfModule = await import('../workflow.js');
  const wfPluginDir = await wfModule.deriveWorkflowPluginDir(stateFile);
  const cmdEnv = wfPluginDir
    ? { ...process.env, WORKFLOW_PLUGIN_DIR: wfPluginDir }
    : { ...process.env };

  try {
    const { stdout, stderr } = await execAsync(step.command, { timeout: 300000, env: cmdEnv });
    const timestamp = new Date().toISOString();
    await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command, exit_code: 0, timestamp,
    });
    await stateSetStepOutput(stateFile, stepIndex, stdout || stderr);
    await stateSetStepStatus(stateFile, stepIndex, 'done');

    // FR-008: terminal step — set status=completed; no cascade after.
    if ((step as any).terminal === true) {
      const state = await stateRead(stateFile);
      await stateWrite(stateFile, { ...state, status: 'completed' as const });
      await wheelLog('dispatch_cascade_halt', {
        step_id: step.id, step_type: step.type,
        reason: 'terminal', state_file: stateFile,
      });
      return { decision: 'approve' };
    }

    // FR-002 — cascade to next step after success. Imported lazily to
    // avoid the circular dep (dispatch.ts imports this file).
    const dispatchModule = await import('../dispatch.js');
    return (dispatchModule as any).cascadeNext(hookType, hookInput, stateFile, stepIndex + 1, depth);
  } catch (err) {
    const exitCode = (err as NodeJS.ErrnoException).code ?? 1;
    await stateModule.stateAppendCommandLog(stateFile, stepIndex, {
      command: step.command ?? '', exit_code: exitCode as number,
      timestamp: new Date().toISOString(),
    });
    await stateSetStepStatus(stateFile, stepIndex, 'failed');
    // FR-008 — cascade halts on failure. Set state.status='failed' so
    // the archive helper routes to history/failure/.
    const fresh = await stateRead(stateFile);
    await stateWrite(stateFile, { ...fresh, status: 'failed' as const });
    await wheelLog('dispatch_cascade_halt', {
      step_id: step.id, step_type: step.type,
      reason: 'failed', state_file: stateFile,
    });
    return { decision: 'approve' };
  }
}
