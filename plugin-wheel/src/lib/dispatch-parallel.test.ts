// FR-007 A1 — minimal dispatchParallel parity sanity test.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-parallel-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('dispatchParallel basic-dispatch', () => {
  it('stop hook on pending step transitions to working and emits agent list', async () => {
    const statePath = path.join(TEST_DIR, 'parallel.json');
    const step = { id: 'p1', type: 'parallel', agents: ['a', 'b', 'c'], instruction: 'Do work.' };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);

    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('a, b, c');

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0].status).toBe('working');
  });
});
