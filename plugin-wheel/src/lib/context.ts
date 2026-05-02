// FR-006: Context building for agent instructions
import type { WorkflowStep, WheelState, WorkflowDefinition } from '../shared/state.js';

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

// parity: shell context.sh:274 — context_capture_output. Thin wrapper that
// stores the captured output value (file path or inline string) into
// state.steps[stepIndex].output via state_set_step_output. Replaces the
// pre-fix regression where dispatchAgent set output to null on advance.
export async function contextCaptureOutput(
  stateFile: string,
  stepIndex: number,
  outputValue: unknown,
): Promise<void> {
  const stateModule = await import('./state.js');
  await stateModule.stateSetStepOutput(stateFile, stepIndex, outputValue);
}

// parity: shell context.sh:341 — context_write_teammate_files. Writes
// per-teammate context.json + assignment.json into the teammate's
// output_dir before the orchestrator spawns the agent.
//
// Behaviour:
//   * mkdir -p outputDir
//   * context.json: collects outputs of context_from step IDs from
//     parent state. If an output value is a file path that exists,
//     reads file contents; else uses the raw output string.
//   * assignment.json: serialised assignJson (defaults to {}).
export async function contextWriteTeammateFiles(
  outputDir: string,
  state: WheelState,
  workflow: WorkflowDefinition,
  contextFromJson: unknown[],
  assignJson: Record<string, unknown>,
): Promise<void> {
  const { promises: fs } = await import('fs');
  const path = (await import('path')).default;

  await fs.mkdir(outputDir, { recursive: true });

  const contextData: Record<string, unknown> = {};
  const depIds = Array.isArray(contextFromJson) ? contextFromJson : [];
  for (const raw of depIds) {
    const depId = String(raw ?? '');
    if (!depId) continue;
    const depIndex = workflow.steps.findIndex(s => s.id === depId);
    if (depIndex < 0) continue;
    const depOutput = state.steps[depIndex]?.output;
    if (depOutput == null || depOutput === '') continue;
    const outStr = typeof depOutput === 'string' ? depOutput : JSON.stringify(depOutput);
    // If output value is a file path that exists, read its contents.
    let resolved = outStr;
    if (typeof depOutput === 'string') {
      try {
        const stat = await fs.stat(depOutput);
        if (stat.isFile()) {
          resolved = await fs.readFile(depOutput, 'utf-8');
        }
      } catch {
        // not a file — leave raw value
      }
    }
    contextData[depId] = resolved;
  }
  await fs.writeFile(path.join(outputDir, 'context.json'), JSON.stringify(contextData, null, 2) + '\n');
  await fs.writeFile(path.join(outputDir, 'assignment.json'), JSON.stringify(assignJson ?? {}, null, 2) + '\n');
}