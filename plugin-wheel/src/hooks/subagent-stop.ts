// FR-007: SubagentStop hook entry point
//
// Wakes the engine when a sub-agent (teammate Agent) terminates. Calls
// engineHandleHook('subagent_stop') which (per FR-005 of wait-all redesign)
// remaps to 'post_tool_use' when the parent's current step is team-wait,
// triggering the polling backstop re-check. Pre-existing wiring gap fixed
// alongside stop.ts.
import { stateRead } from '../shared/state.js';
import { engineInit, engineHandleHook } from '../lib/engine.js';
import { resolveStateFile } from '../lib/guard.js';
import type { HookInput } from '../lib/dispatch.js';

async function readStdin(): Promise<string> {
  return await new Promise<string>((resolve, reject) => {
    let data = '';
    process.stdin.on('data', (chunk: Buffer) => {
      data += chunk.toString();
    });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

async function main(): Promise<void> {
  try {
    const input: HookInput = JSON.parse(await readStdin());
    const stateFile = await resolveStateFile('.wheel', input);
    if (!stateFile) {
      console.log(JSON.stringify({ decision: 'approve' }));
      return;
    }

    let workflowFile = '';
    try {
      const state = await stateRead(stateFile);
      workflowFile = state.workflow_file ?? '';
    } catch {
      console.log(JSON.stringify({ decision: 'approve' }));
      return;
    }
    if (!workflowFile) {
      console.log(JSON.stringify({ decision: 'approve' }));
      return;
    }
    await engineInit(workflowFile, stateFile);

    const output = await engineHandleHook('subagent_stop', input);
    console.log(JSON.stringify(output));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main();
