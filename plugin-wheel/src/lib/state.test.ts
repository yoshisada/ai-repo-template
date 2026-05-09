// Scenario: S5 — stateInit creates valid state, stateGetCursor/stateSetCursor work
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { stateInit, stateGetCursor, stateSetCursor, stateGetStepStatus, stateSetStepStatus } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-lib-state-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('stateInit', () => {
  it('should create a valid state file with correct structure', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'state.json');
    await stateInit({
      stateFile: statePath,
      workflow: {
        name: 'test-workflow',
        version: '1.0.0',
        steps: [{ id: 's1', type: 'command' }, { id: 's2', type: 'agent' }],
      },
      sessionId: 'session-1',
      agentId: 'agent-1',
    });

    const state = await stateRead(statePath);
    expect(state.workflow_name).toBe('test-workflow');
    expect(state.status).toBe('running');
    expect(state.cursor).toBe(0);
    expect(state.steps.length).toBe(2);
    expect(state.steps[0].id).toBe('s1');
    expect(state.steps[0].status).toBe('pending');
    expect(state.steps[1].id).toBe('s2');
  });

  it('should set started_at and updated_at timestamps', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'state-init-test.json');
    const before = Date.now();
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'ts', version: '1.0', steps: [] },
      sessionId: 's1',
      agentId: '',
    });
    const state = await stateRead(statePath);
    expect(new Date(state.started_at).getTime()).toBeGreaterThanOrEqual(before);
    expect(new Date(state.updated_at).getTime()).toBeGreaterThanOrEqual(before);
  });
});

describe('stateGetCursor', () => {
  it('should return current cursor value', () => { // FR-006
    const state = { cursor: 3 } as any;
    expect(stateGetCursor(state)).toBe(3);
  });
});

describe('stateSetCursor', () => {
  it('should update cursor in state file', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'cursor-test.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 't', version: '1.0', steps: [{ id: 's', type: 'c' }] },
      sessionId: 's1',
      agentId: '',
    });
    await stateSetCursor(statePath, 5);
    const state = await stateRead(statePath);
    expect(state.cursor).toBe(5);
  });
});

describe('stateGetStepStatus', () => {
  it('should return step status', () => { // FR-006
    const state = {
      steps: [{ status: 'working' }, { status: 'pending' }],
    } as any;
    expect(stateGetStepStatus(state, 0)).toBe('working');
    expect(stateGetStepStatus(state, 1)).toBe('pending');
  });

  it('should return pending for non-existent step', () => { // FR-006
    const state = { steps: [] } as any;
    expect(stateGetStepStatus(state, 99)).toBe('pending');
  });
});

describe('stateSetStepStatus', () => {
  it('should set working and record started_at', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'step-status.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 't', version: '1.0', steps: [{ id: 's', type: 'c' }] },
      sessionId: 's1',
      agentId: '',
    });
    await stateSetStepStatus(statePath, 0, 'working');
    const state = await stateRead(statePath);
    expect(state.steps[0].status).toBe('working');
    expect(state.steps[0].started_at).toBeTruthy();
  });

  it('should set done and record completed_at', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'step-done.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 't', version: '1.0', steps: [{ id: 's', type: 'c' }] },
      sessionId: 's1',
      agentId: '',
    });
    await stateSetStepStatus(statePath, 0, 'done');
    const state = await stateRead(statePath);
    expect(state.steps[0].status).toBe('done');
    expect(state.steps[0].completed_at).toBeTruthy();
  });
});

describe('alternateAgentId support', () => {
  it('should store alternateAgentId in state when provided', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'alternate-agent-id.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 't', version: '1.0', steps: [{ id: 's', type: 'c' }] },
      sessionId: 's1',
      agentId: '',
      alternateAgentId: 'worker-1@test-team',
    });
    const state = await stateRead(statePath);
    expect((state as any).alternate_agent_id).toBe('worker-1@test-team');
  });

  it('should allow later update of alternate_agent_id', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'alternate-agent-id-update.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 't', version: '1.0', steps: [{ id: 's', type: 'c' }] },
      sessionId: 's1',
      agentId: '',
    });
    const state = await stateRead(statePath);
    (state as any).alternate_agent_id = 'worker-1@test-team';
    await stateWrite(statePath, state);
    const updated = await stateRead(statePath);
    expect((updated as any).alternate_agent_id).toBe('worker-1@test-team');
  });
});