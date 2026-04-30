// Scenario: S7 — status should be 'completed' when workflow finishes via terminal step
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { stateInit } from './state.js';
import { dispatchStep } from './dispatch.js';
import { stateRead } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-status-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('workflow status after terminal command step', () => {
  it('should set status to completed after terminal command step executes', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'terminal-status.json');
    await stateInit({
      stateFile: statePath,
      workflow: {
        name: 'test-terminal',
        version: '1.0',
        steps: [{ id: 's1', type: 'command', command: 'echo done', terminal: true }],
      },
      sessionId: 's1',
      agentId: '',
    });

    // Dispatch with post_tool_use so command actually executes
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo done', terminal: true } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );

    // After terminal step, state should be archived with status=completed
    // (The archived file should have status: 'completed', not 'running')
    // Since state file is deleted on archive, we check by trying to read it
    // The hook handles archive + deletion; after dispatch, state should be gone
    // But the key assertion is: the status at time of archive should be 'completed'
    // We verify this by checking that handleNormalPath would set completed before archiving
    const state = await stateRead(statePath);
    expect(state.status).toBe('completed');
  });
});