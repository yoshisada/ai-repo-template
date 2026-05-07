// PostToolUse hook entry point.
//
// This file is a thin router: it reads stdin, classifies the tool call
// (deactivate.sh / activate.sh / normal), and dispatches to the matching
// handler under `post-tool-use/`.
//
// Single source of truth per concern:
//   - extractors.ts        — text-extraction primitives
//   - resolve-workflow.ts  — workflow file resolution + plugin discovery
//   - handle-activate.ts   — activate.sh handler
//   - handle-deactivate.ts — deactivate.sh handler
//   - handle-normal-path.ts — non-activate hook handler
//
// FR-007 (PostToolUse hook entry); FR-C1 (newline preservation);
// FR-F3-1 (pre-flight resolver).

import { stateRead } from '../shared/state.js';
import type { HookInput, HookOutput } from '../lib/dispatch.js';
import {
  readStdin,
  extractCommandWithFallback,
  parseHookInputWithFallback,
  detectActivateLine,
} from './post-tool-use/extractors.js';
import { handleActivation } from './post-tool-use/handle-activate.js';
import { handleDeactivate } from './post-tool-use/handle-deactivate.js';
import {
  handleNormalPath,
  listMatchingStateFiles,
} from './post-tool-use/handle-normal-path.js';
import { emitHookOutput } from './emit.js';

// Re-export for callers (engine.ts, tests) that still import these
// from the entry-point file.
export { handleNormalPath, handleDeactivate };

async function main(): Promise<void> {
  try {
    const rawInput = await readStdin();
    const command = await extractCommandWithFallback(rawInput);
    // FR-C1 fallback: rawInput may contain literal control chars (the actual
    // hook payload shape Claude Code's harness emits) — JSON.parse rejects,
    // python3 strict=False accepts. Use the same fallback both extractors share.
    const parsed = await parseHookInputWithFallback(rawInput);
    if (!parsed || typeof parsed !== 'object') {
      // Both parsers failed — emit empty hook output and exit gracefully.
      await emitHookOutput({ hookEventName: 'PostToolUse' });
      return;
    }
    const hookInput = parsed as HookInput;

    // parity: shell post-tool-use.sh:83 — handle deactivate.sh BEFORE
    // activate.sh (substring overlap).
    if (command.includes('deactivate.sh')) {
      const output = await handleDeactivate(command, hookInput);
      await emitHookOutput(output);
      return;
    }

    const activateLine = detectActivateLine(command);
    if (activateLine) {
      const { output } = await handleActivation(activateLine, hookInput);
      await emitHookOutput(output);
      return;
    }

    // P3 fix: loop over ALL matching state files. With composition / team
    // workflows, parent + child can share owner_session_id. The pre-fix
    // single-state-file path always returned the first match (typically
    // the parent), so the child never advanced.
    //
    // Output-aggregation policy: a `block` decision from ANY state file
    // wins (so the orchestrator stays blocked until the most stringent
    // workflow gets unblocked). LAST block's `additionalContext` is kept.
    const stateFiles = await listMatchingStateFiles('.wheel', hookInput);
    if (stateFiles.length === 0) {
      await emitHookOutput({ hookEventName: 'PostToolUse' });
      return;
    }

    let aggregatedOutput: HookOutput = { hookEventName: 'PostToolUse' };
    let sawBlock = false;
    for (const stateFile of stateFiles) {
      let state;
      try {
        state = await stateRead(stateFile);
      } catch { continue; }
      if (!state.workflow_file) continue;

      let out: HookOutput;
      try {
        out = await handleNormalPath(hookInput, stateFile);
      } catch (err) {
        console.error('Engine error:', err);
        continue;
      }

      if (out.decision === 'block') {
        aggregatedOutput = out;
        sawBlock = true;
      } else if (!sawBlock) {
        aggregatedOutput = out;
      }
    }
    await emitHookOutput(aggregatedOutput);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}

// Only invoke main() when this module is the entry point (allows
// individual handlers to be tested without triggering hook execution).
const mainScript = process.argv[1] ?? '';
if (mainScript.endsWith('post-tool-use.js') || mainScript.endsWith('post-tool-use.ts')) {
  main();
}
