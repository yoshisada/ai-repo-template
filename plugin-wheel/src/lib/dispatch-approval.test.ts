// FR-007 A2 — dispatchApproval parity test.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-approval-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('dispatchApproval approval-teammate-idle', () => {
  it('teammate_idle with approval=approved advances cursor', async () => {
    const statePath = path.join(TEST_DIR, 'approve.json');
    const step = { id: 'a1', type: 'approval', message: 'Continue?' };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any, { id: 'a2', type: 'command' }] },
      sessionId: 's',
      agentId: '',
    });

    // first stop puts step in working + block
    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    // teammate_idle with approval=approved advances cursor
    const result = await dispatchStep(
      step as any,
      'teammate_idle',
      { approval: 'approved' } as any,
      statePath,
      0,
    );

    expect(result.decision).toBe('approve');
    const finalState = await stateRead(statePath);
    expect(finalState.steps[0].status).toBe('done');
    expect(finalState.cursor).toBe(1);
  });

  it('teammate_idle without approval keeps blocking', async () => {
    const statePath = path.join(TEST_DIR, 'wait.json');
    const step = { id: 'a1', type: 'approval' };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    const result = await dispatchStep(
      step as any,
      'teammate_idle',
      {} as any,
      statePath,
      0,
    );

    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('WAITING FOR APPROVAL');
  });
});
