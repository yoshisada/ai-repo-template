// Terminal step unit test
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { stateInit } from './state.js';
import { dispatchStep } from './dispatch.js';
import { stateRead } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-terminal-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('terminal step dispatch', () => {
  it('should set status=completed when terminal step dispatches', async () => { // FR-006
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

    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo done', terminal: true } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );

    const state = await stateRead(statePath);
    expect(state.status).toBe('completed');
  });
});