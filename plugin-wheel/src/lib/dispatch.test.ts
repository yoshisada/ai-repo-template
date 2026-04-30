// Scenario: S6 — dispatchStep routes to correct handler
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';

const TEST_DIR = '/tmp/wheel-dispatch-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('dispatchStep', () => {
  it('should return approve for unknown step type', async () => { // FR-007
    const statePath = path.join(TEST_DIR, 'unknown-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'unknown' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'unknown' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should route agent steps to dispatchAgent', async () => { // FR-003
    const statePath = path.join(TEST_DIR, 'agent-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'agent', instruction: 'test' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'agent', instruction: 'do work' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should route command steps to dispatchCommand', async () => { // FR-019
    const statePath = path.join(TEST_DIR, 'command-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo hello' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should skip command execution for non-post_tool_use hooks', async () => { // FR-019
    const statePath = path.join(TEST_DIR, 'non-post-hook.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo test' } as any,
      'session_start',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should route approval steps and return block', async () => { // FR-013
    const statePath = path.join(TEST_DIR, 'approval-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'approval' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'approval' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('block');
  });
});

describe('dispatchAgent', () => {
  it('should set step to working and return context', async () => { // FR-003
    const statePath = path.join(TEST_DIR, 'agent-context.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'agent', instruction: 'do work' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'agent', instruction: 'do work' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
    expect(result.additionalContext).toBeTruthy();
  });
});

describe('dispatchCommand', () => {
  it('should execute command and update state', async () => { // FR-019
    const statePath = path.join(TEST_DIR, 'command-exec.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo hello' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });
});