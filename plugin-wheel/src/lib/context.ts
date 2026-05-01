// FR-006: Context building for agent instructions
import type { WorkflowStep, WheelState } from '../shared/state.js';

// FR-006: contextBuild(step: WorkflowStep, state: WheelState, resolvedInputs: unknown): Promise<string>
export async function contextBuild(
  step: WorkflowStep,
  state: WheelState,
  resolvedInputs: unknown
): Promise<string> {
  const lines: string[] = [];

  // Step description
  if (step.id) {
    lines.push(`## Step: ${step.id}`);
  }
  if (step.type) {
    lines.push(`**Type**: ${step.type}`);
  }

  // Previous step output
  const prevIndex = state.cursor - 1;
  if (prevIndex >= 0 && prevIndex < state.steps.length) {
    const prevStep = state.steps[prevIndex];
    if (prevStep.output) {
      lines.push('');
      lines.push('## Previous Step Output');
      lines.push(String(prevStep.output));
    }
    if (prevStep.command_log.length > 0) {
      lines.push('');
      lines.push('## Command Log');
      for (const entry of prevStep.command_log) {
        lines.push(`- \`${entry.command}\` (exit: ${entry.exit_code})`);
      }
    }
  }

  // Resolved inputs
  if (resolvedInputs) {
    lines.push('');
    lines.push('## Resolved Inputs');
    lines.push(JSON.stringify(resolvedInputs, null, 2));
  }

  // Loop iteration context
  if (typeof step.loop_iteration === 'number' && step.loop_iteration > 0) {
    lines.push('');
    lines.push(`**Loop Iteration**: ${step.loop_iteration}`);
  }

  return lines.join('\n');
}