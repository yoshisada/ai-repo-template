// Scenario: S4 — stateRead and stateWrite preserve schema, updated_at is set on write
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { stateRead, stateWrite, WheelState } from './state.js';

const TEST_DIR = '/tmp/wheel-state-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('stateRead', () => {
  it('should parse valid state file', async () => { // FR-005
    const statePath = path.join(TEST_DIR, 'state.json');
    const state: WheelState = {
      workflow_name: 'test-workflow',
      workflow_version: '1.0.0',
      workflow_file: '/test/workflow.json',
      workflow_definition: null,
      status: 'running',
      cursor: 0,
      owner_session_id: 'session-1',
      owner_agent_id: '',
      started_at: '2026-04-29T10:00:00Z',
      updated_at: '2026-04-29T10:00:00Z',
      steps: [],
      teams: {},
      session_registry: null,
    };
    await fs.writeFile(statePath, JSON.stringify(state));
    const result = await stateRead(statePath);
    expect(result.workflow_name).toBe('test-workflow');
    expect(result.status).toBe('running');
  });

  it('should throw on invalid JSON', async () => { // FR-005
    const statePath = path.join(TEST_DIR, 'invalid.json');
    await fs.writeFile(statePath, 'not valid json');
    await expect(stateRead(statePath)).rejects.toThrow();
  });
});

describe('stateWrite', () => {
  it('should write state and set updated_at', async () => { // FR-005
    const statePath = path.join(TEST_DIR, 'written-state.json');
    const state: WheelState = {
      workflow_name: 'write-test',
      workflow_version: '1.0.0',
      workflow_file: '/test/workflow.json',
      workflow_definition: null,
      status: 'running',
      cursor: 0,
      owner_session_id: 'session-1',
      owner_agent_id: '',
      started_at: '2026-04-29T10:00:00Z',
      updated_at: '2026-04-29T10:00:00Z',
      steps: [],
      teams: {},
      session_registry: null,
    };
    const before = Date.now();
    await stateWrite(statePath, state);
    const result = await stateRead(statePath);
    expect(result.updated_at).toBeTruthy();
    const updatedTime = new Date(result.updated_at).getTime();
    expect(updatedTime).toBeGreaterThanOrEqual(before);
  });

  it('should preserve all state fields', async () => { // FR-005
    const statePath = path.join(TEST_DIR, 'full-state.json');
    const state: WheelState = {
      workflow_name: 'full-test',
      workflow_version: '2.0.0',
      workflow_file: '/test/workflow.json',
      workflow_definition: { name: 'test', version: '2.0.0', steps: [] },
      status: 'completed',
      cursor: 5,
      owner_session_id: 'session-2',
      owner_agent_id: 'agent-1',
      started_at: '2026-04-29T10:00:00Z',
      updated_at: '2026-04-29T11:00:00Z',
      steps: [{ id: 's1', type: 'command', status: 'done', started_at: null, completed_at: null, output: 'done', command_log: [], agents: {}, loop_iteration: 0, awaiting_user_input: false, awaiting_user_input_since: null, awaiting_user_input_reason: null, resolved_inputs: null, contract_emitted: false }],
      teams: {},
      session_registry: { kiln: '/path/to/kiln' },
    };
    await stateWrite(statePath, state);
    const result = await stateRead(statePath);
    expect(result.workflow_name).toBe('full-test');
    expect(result.cursor).toBe(5);
    expect(result.steps[0].id).toBe('s1');
  });
});