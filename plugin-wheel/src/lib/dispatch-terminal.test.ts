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

  // FR-005 A1 — composition child-archive advances parent
  it('child-archive-advances-parent: composition parent cursor advances when child archives', async () => {
    // Construct a parent with a workflow-step in 'working' status and a child
    // with parent_workflow set. Calling archiveWorkflow on the child should
    // mark the parent's workflow step done and bump its cursor.
    const stateModule = await import('./state.js');
    const parentPath = path.join(TEST_DIR, 'parent.json');
    const parentSteps = [
      { id: 'p1', type: 'workflow' as const },
      { id: 'p2', type: 'command' as const, command: 'true' },
    ];
    await stateInit({
      stateFile: parentPath,
      workflow: { name: 'parent', version: '1.0', steps: parentSteps },
      sessionId: 's',
      agentId: '',
    });
    {
      const s = await stateRead(parentPath);
      (s as any).workflow_definition = { name: 'parent', version: '1.0', steps: parentSteps };
      s.steps[0].status = 'working';
      s.cursor = 0;
      await (await import('../shared/state.js')).stateWrite(parentPath, s);
    }

    const childPath = path.join(TEST_DIR, 'child.json');
    await stateInit({
      stateFile: childPath,
      workflow: { name: 'child', version: '1.0', steps: [{ id: 'c1', type: 'command' }] },
      sessionId: 's',
      agentId: '',
      parentWorkflow: parentPath,
    });

    await stateModule.archiveWorkflow(childPath, 'success');

    const finalParent = await stateRead(parentPath);
    expect(finalParent.steps[0].status).toBe('done');
    expect(finalParent.cursor).toBe(1);
  });
});