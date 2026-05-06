// dispatchWorkflow — handles `type: "workflow"` (child workflow composition).
//
// Stop / PostToolUse (pending): activate the child workflow as a separate
//   state file (`state_child_<name>_<ts>_<rand>.json`), record `parent_workflow`
//   so archiveWorkflow can resume the parent on child terminal. Then kick
//   off the child's first auto-executable step inside this same hook fire
//   so its cascade runs back-to-back (matches shell wheel's recursion).
//   Returns block "Child workflow activated: <name>".
// working: returns block "Waiting for child workflow to complete: <name>".
//
// FR-014, FR-001 Composite / US-5.

import type { WorkflowStep } from '../../shared/state.js';
import { stateRead, stateWrite } from '../../shared/state.js';
import { stateSetStepStatus } from '../state.js';
import { isAutoExecutable } from '../dispatch-types.js';
import type { HookInput, HookOutput, HookType } from '../dispatch-types.js';

export async function dispatchWorkflow(
  step: WorkflowStep,
  hookType: HookType,
  hookInput: HookInput,
  stateFile: string,
  stepIndex: number,
): Promise<HookOutput> {
  if (hookType !== 'stop' && hookType !== 'post_tool_use') {
    return { decision: 'approve' };
  }

  const stateModule = await import('../state.js');
  const state = await stateRead(stateFile);
  const stepStatus = state.steps[stepIndex]?.status ?? 'pending';

  if (stepStatus === 'pending') {
    await stateSetStepStatus(stateFile, stepIndex, 'working');
    const childName = (step as any).workflow;
    if (!childName) return { decision: 'approve' };

    const safeChildName = String(childName).replace(/\//g, '-');
    const childUnique = `child_${safeChildName}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const childStateFile = `.wheel/state_${childUnique}.json`;

    const workflowModule = await import('../workflow.js');
    let childFile = `workflows/${childName}.json`;
    if (String(childName).includes(':')) {
      childFile = `workflows/${String(childName).split(':')[1]}.json`;
    }

    let childJson: any;
    try {
      childJson = await workflowModule.workflowLoad(childFile);
    } catch {
      await stateSetStepStatus(stateFile, stepIndex, 'failed');
      return { decision: 'approve' };
    }

    await stateModule.stateInit({
      stateFile: childStateFile,
      workflow: childJson,
      sessionId: state.owner_session_id ?? '',
      agentId: state.owner_agent_id ?? '',
      // parity: shell dispatch.sh:144 — child must know its parent so
      // archiveWorkflow can resume the parent on child terminal.
      parentWorkflow: stateFile,
    });

    try {
      const persistedChild = await stateRead(childStateFile);
      (persistedChild as any).workflow_definition = childJson;
      await stateWrite(childStateFile, persistedChild);
    } catch { /* non-fatal */ }

    const engineModule = await import('../engine.js');
    try {
      await engineModule.engineKickstart(childStateFile);
    } catch { /* non-fatal */ }

    // FR-001 Composite / US-5 — child cascade kicked off in child state.
    const childSteps = childJson.steps ?? [];
    if (childSteps.length > 0 && isAutoExecutable(childSteps[0])) {
      try {
        const dispatchModule = await import('../dispatch.js');
        await dispatchModule.dispatchStep(childSteps[0] as WorkflowStep, 'post_tool_use', hookInput, childStateFile, 0, 0);
      } catch { /* non-fatal: child cascade error swallowed (parity hygiene) */ }
      try {
        await engineModule.maybeArchiveAfterActivation(childStateFile);
      } catch { /* non-fatal */ }
    }

    return {
      decision: 'block',
      additionalContext: `Child workflow activated: ${childName}`,
    };
  }
  if (stepStatus === 'working') {
    const childName = (step as any).workflow ?? 'unknown';
    return {
      decision: 'block',
      additionalContext: `Waiting for child workflow to complete: ${childName}`,
    };
  }
  return { decision: 'approve' };
}
