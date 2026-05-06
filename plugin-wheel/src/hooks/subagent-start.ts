// FR-007: SubagentStart hook entry point
import { engineHandleHook } from '../lib/engine.js';
import type { HookInput } from '../shared/index.js';
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
    const output = await engineHandleHook('subagent_start', input);
    await emitHookOutput(output);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main();
