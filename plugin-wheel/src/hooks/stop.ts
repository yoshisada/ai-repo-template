// FR-007: Stop hook entry point
//
// Reads the hook payload from stdin, resolves the active state file owned
// by the calling agent, initializes the engine with that state, then routes
// the 'stop' event through engineHandleHook. Without this resolution + init
// dance, engineHandleHook short-circuits because its module-level STATE_FILE
// is empty — which silently disables every team-create / agent / team-wait
// prompt injection that depends on the Stop hook firing. Pre-existing gap
// in the rewrite caught during wheel-wait-all-redesign (B-3 verification).
import { stateRead } from '../shared/state.js';
import { engineInit, engineHandleHook } from '../lib/engine.js';
import { resolveStateFile } from '../lib/guard.js';
import type { HookInput } from '../lib/dispatch.js';
import { emitHookOutput } from './emit.js';

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

    const output = await engineHandleHook('stop', input);
    await emitHookOutput(output);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main();
