// P2 round-1 regression — workflowLoad accepts both raw workflow JSON
// paths AND state-file paths. Pre-fix it always read via stateRead and
// threw ValidationError on workflow JSON files (the inner catch rethrew
// the validation error before reaching the direct-read fallback).
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { workflowLoad } from './workflow.js';

const TEST_DIR = '/tmp/wheel-workflow-load-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('workflowLoad: workflow JSON path', () => {
  it('accepts a raw workflow JSON file (the dispatchWorkflow case)', async () => {
    const wfPath = path.join(TEST_DIR, 'wf.json');
    const wf = {
      name: 'composed-child',
      version: '1.0',
      steps: [
        { id: 's1', type: 'command' },
        { id: 's2', type: 'agent' },
      ],
    };
    await fs.writeFile(wfPath, JSON.stringify(wf));

    const loaded = await workflowLoad(wfPath);

    expect(loaded.name).toBe('composed-child');
    expect(loaded.steps.length).toBe(2);
  });

  it('accepts a state file with workflow_definition embedded', async () => {
    const sfPath = path.join(TEST_DIR, 'state.json');
    const wf = {
      name: 'embedded',
      version: '1.0',
      steps: [{ id: 's1', type: 'command' }],
    };
    const stateLike = {
      workflow_name: 'embedded',
      workflow_definition: wf,
      workflow_file: '',
      cursor: 0,
      steps: [{ id: 's1', type: 'command', status: 'pending' }],
    };
    await fs.writeFile(sfPath, JSON.stringify(stateLike));

    const loaded = await workflowLoad(sfPath);
    expect(loaded.name).toBe('embedded');
  });

  it('accepts a state file with only workflow_file set (recurses)', async () => {
    const wfPath = path.join(TEST_DIR, 'wf2.json');
    const wf = {
      name: 'pointed',
      version: '1.0',
      steps: [{ id: 's1', type: 'command' }],
    };
    await fs.writeFile(wfPath, JSON.stringify(wf));

    const sfPath = path.join(TEST_DIR, 'state2.json');
    const stateLike = {
      workflow_name: 'pointed',
      workflow_definition: null,
      workflow_file: wfPath,
      cursor: 0,
      steps: [{ id: 's1', type: 'command', status: 'pending' }],
    };
    await fs.writeFile(sfPath, JSON.stringify(stateLike));

    const loaded = await workflowLoad(sfPath);
    expect(loaded.name).toBe('pointed');
  });

  it('throws StateNotFoundError when path does not exist', async () => {
    await expect(workflowLoad(path.join(TEST_DIR, 'missing.json'))).rejects.toThrow();
  });
});
