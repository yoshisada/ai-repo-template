// FR-003 — dispatchLoop self-cascade + max_iterations from workflow def
// Closes #199 Bug A (no self-cascade between iters) and Bug B
// (max_iterations sourced from state instead of workflow def).
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-loop-iter-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('dispatchLoop: max_iterations from workflow def', () => {
  it('runs to max_iterations:50 in a single hook fire (Bug A self-cascade)', async () => {
    const statePath = path.join(TEST_DIR, 'loop-50.json');
    const counterFile = path.join(TEST_DIR, 'count.txt');
    await fs.writeFile(counterFile, '0');

    const step = {
      id: 's1',
      type: 'loop',
      max_iterations: 50,
      substep: {
        type: 'command',
        // increment counter
        command: `n=$(cat ${counterFile}); echo $((n+1)) > ${counterFile}`,
      },
    };

    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's1',
      agentId: '',
    });

    const result = await dispatchStep(step as any, 'post_tool_use', {}, statePath, 0);
    expect(result.decision).toBe('approve');

    const finalCount = parseInt(await fs.readFile(counterFile, 'utf-8'), 10);
    expect(finalCount).toBe(50);

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0]?.status).toBe('done');
  }, 30000);

  it('reads max_iterations from workflow def, not state.steps[i] (Bug B)', async () => {
    // Bug B regression test: prior code read max_iterations from state.steps[i],
    // which is never written, so default of 10 always kicked in. This test
    // sets max_iterations:25 in the step (workflow def) and expects 25 iters.
    const statePath = path.join(TEST_DIR, 'loop-25.json');
    const counterFile = path.join(TEST_DIR, 'count.txt');
    await fs.writeFile(counterFile, '0');

    const step = {
      id: 's1',
      type: 'loop',
      max_iterations: 25,
      substep: {
        type: 'command',
        command: `n=$(cat ${counterFile}); echo $((n+1)) > ${counterFile}`,
      },
    };

    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's1',
      agentId: '',
    });

    await dispatchStep(step as any, 'post_tool_use', {}, statePath, 0);

    const finalCount = parseInt(await fs.readFile(counterFile, 'utf-8'), 10);
    expect(finalCount).toBe(25);
  }, 30000);

  it('exits early when condition is met before max_iterations', async () => {
    const statePath = path.join(TEST_DIR, 'loop-cond.json');

    // condition `true` (exit 0) → loop body marks done before incrementing.
    const step = {
      id: 's1',
      type: 'loop',
      max_iterations: 100,
      condition: 'true',
      substep: {
        type: 'command',
        command: 'true',
      },
    };

    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's1',
      agentId: '',
    });

    const result = await dispatchStep(step as any, 'post_tool_use', {}, statePath, 0);
    expect(result.decision).toBe('approve');

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0]?.status).toBe('done');
    // loop_iteration should remain 0 because we exit early before incrementing.
    expect((finalState.steps[0] as any)?.loop_iteration ?? 0).toBe(0);
  });
});
