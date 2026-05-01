// FR-007: TeammateIdle hook entry point
//
// Wakes the engine when a teammate goes idle. Same wiring as stop.ts /
// subagent-stop.ts — without it, engineHandleHook short-circuits on empty
// STATE_FILE and the FR-005 wake-up nudge never reaches dispatchTeamWait.
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

    const output = await engineHandleHook('teammate_idle', input);
    console.log(JSON.stringify(output));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main();
