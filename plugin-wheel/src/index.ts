// FR-008: Unified CLI router for wheel TypeScript implementation
import { engineHandleHook } from './lib/engine.js';
import type { HookType, HookInput } from './shared/index.js';

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
  const hookType = process.argv[2] as HookType;
  if (!hookType) {
    console.error('Usage: wheel <hook-type>');
    process.exit(1);
  }

  try {
    const stdinData = await readStdin();
    const input: HookInput = stdinData ? JSON.parse(stdinData) : {};
    const output = await engineHandleHook(hookType, input);
    console.log(JSON.stringify(output));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});