// FR-007: PostToolUse hook entry point
import { engineHandleHook } from '../lib/engine.js';
import type { HookInput } from '../shared/index.js';

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
    const output = await engineHandleHook('post_tool_use', input);
    console.log(JSON.stringify(output));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main();