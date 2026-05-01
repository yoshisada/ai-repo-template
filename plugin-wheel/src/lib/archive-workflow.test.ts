// Tests for FR-001, FR-002, FR-006, FR-007, FR-008, FR-009 (wheel-wait-all-redesign)
// archiveWorkflow + parent-state helpers in state.ts.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import {
  archiveWorkflow,
  stateUpdateParentTeammateSlot,
  maybeAdvanceParentTeamWaitCursor,
  stateInit,
  stateAddTeammate,
  stateUpdateTeammateStatus,
} from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-archive-test';
let testCounter = 0;
let activeDir: string;

beforeEach(async () => {
  testCounter++;
  activeDir = path.join(TEST_ROOT, `t-${testCounter}-${Date.now()}`);
  await fs.mkdir(activeDir, { recursive: true });
  // archiveWorkflow uses cwd-relative .wheel/history paths.
  process.chdir(activeDir);
  await fs.mkdir('.wheel', { recursive: true });
});

afterEach(async () => {
  process.chdir('/tmp');
  await fs.rm(activeDir, { recursive: true, force: true });
});

async function makeParent(opts: {
  cursor?: number;
  steps?: Array<{ id: string; type: string }>;
  teamId?: string;
  teamName?: string;
  teammates?: Array<{ name: string; agent_id: string; status?: string }>;
}): Promise<string> {
  const stateFile = path.join(activeDir, '.wheel', 'state_parent.json');
  const steps = opts.steps ?? [
    { id: 'team-create-step', type: 'team-create' },
    { id: 'wait-step', type: 'team-wait' },
    { id: 'after-wait', type: 'command' },
  ];
  await stateInit({
    stateFile,
    workflow: { name: 'parent', version: '1.0', steps },
    sessionId: 'sess',
    agentId: 'parent-agent',
  });
  // Inject workflow_definition so maybeAdvance can find the team field.
  const state = await stateRead(stateFile);
  state.workflow_definition = {
    name: 'parent',
    version: '1.0',
    steps: steps.map((s) => ({
      id: s.id,
      type: s.type,
      // For team-wait steps, the `team` field defaults to step id.
      ...(s.type === 'team-wait' ? { team: opts.teamId ?? s.id } : {}),
    })),
  };
  state.cursor = opts.cursor ?? 1;
  await stateWrite(stateFile, state);

  const teamId = opts.teamId ?? 'wait-step';
  const teamName = opts.teamName ?? 'parent-wait-step';
  const { stateSetTeam } = await import('./state.js');
  await stateSetTeam(stateFile, teamId, teamName);
  for (const t of opts.teammates ?? []) {
    await stateAddTeammate(stateFile, teamId, {
      task_id: '',
      status: 'pending',
      agent_id: t.agent_id,
      output_dir: `.wheel/outputs/${t.name}`,
      assign: {},
      started_at: null,
      completed_at: null,
    });
    if (t.status && t.status !== 'pending') {
      await stateUpdateTeammateStatus(stateFile, teamId, t.agent_id, t.status as any);
    }
  }
  return stateFile;
}

async function makeChild(opts: {
  name: string;
  parentPath?: string | null;
  alternateAgentId?: string | null;
  status?: 'running' | 'completed' | 'failed';
}): Promise<string> {
  const stateFile = path.join(
    activeDir,
    '.wheel',
    `state_${opts.name}.json`
  );
  await stateInit({
    stateFile,
    workflow: { name: `child-${opts.name}`, version: '1.0', steps: [{ id: 's1', type: 'command' }] },
    sessionId: 'sess',
    agentId: opts.name,
    alternateAgentId: opts.alternateAgentId ?? undefined,
    parentWorkflow: opts.parentPath ?? undefined,
  });
  if (opts.status) {
    const child = await stateRead(stateFile);
    child.status = opts.status === 'running' ? 'running' : (opts.status as any);
    await stateWrite(stateFile, child);
  }
  return stateFile;
}

// FR-001: stateUpdateParentTeammateSlot
describe('stateUpdateParentTeammateSlot (FR-001)', () => {
  it('updates the matching slot by alternate_agent_id', async () => { // AC US1.1
    const parentPath = await makeParent({
      teammates: [
        { name: 'worker-0', agent_id: 'worker-0@team-x', status: 'running' },
        { name: 'worker-1', agent_id: 'worker-1@team-x', status: 'running' },
      ],
    });

    const result = await stateUpdateParentTeammateSlot(
      parentPath,
      'worker-1@team-x',
      'completed'
    );
    expect(result).toEqual({
      teamId: 'wait-step',
      teammateName: 'worker-1@team-x',
    });
    const parent = await stateRead(parentPath);
    expect(parent.teams['wait-step'].teammates['worker-1@team-x'].status).toBe(
      'completed'
    );
    expect(
      parent.teams['wait-step'].teammates['worker-1@team-x'].completed_at
    ).toBeTruthy();
    // The other slot is untouched.
    expect(parent.teams['wait-step'].teammates['worker-0@team-x'].status).toBe(
      'running'
    );
  });

  it('returns null when no slot matches', async () => { // FR-001
    const parentPath = await makeParent({
      teammates: [
        { name: 'worker-0', agent_id: 'worker-0@team-x', status: 'running' },
      ],
    });
    const result = await stateUpdateParentTeammateSlot(
      parentPath,
      'unknown-agent-id',
      'completed'
    );
    expect(result).toBeNull();
  });

  it('writes failure status for failure bucket (FR-006)', async () => {
    const parentPath = await makeParent({
      teammates: [
        { name: 'worker-0', agent_id: 'worker-0@team-x', status: 'running' },
      ],
    });
    await stateUpdateParentTeammateSlot(
      parentPath,
      'worker-0@team-x',
      'failed'
    );
    const parent = await stateRead(parentPath);
    expect(parent.teams['wait-step'].teammates['worker-0@team-x'].status).toBe(
      'failed'
    );
  });
});

// FR-002: maybeAdvanceParentTeamWaitCursor
describe('maybeAdvanceParentTeamWaitCursor (FR-002)', () => {
  it('advances cursor when all teammates terminal', async () => { // AC US1.1
    const parentPath = await makeParent({
      cursor: 1,
      teammates: [
        { name: 'a', agent_id: 'a@team-x', status: 'completed' },
        { name: 'b', agent_id: 'b@team-x', status: 'completed' },
      ],
    });
    const advanced = await maybeAdvanceParentTeamWaitCursor(
      parentPath,
      'wait-step'
    );
    expect(advanced).toBe(true);
    const parent = await stateRead(parentPath);
    expect(parent.cursor).toBe(2);
    expect(parent.steps[1].status).toBe('done');
    expect(parent.steps[1].completed_at).toBeTruthy();
  });

  it('does not advance when any teammate still running', async () => { // AC US1.2
    const parentPath = await makeParent({
      cursor: 1,
      teammates: [
        { name: 'a', agent_id: 'a@team-x', status: 'completed' },
        { name: 'b', agent_id: 'b@team-x', status: 'running' },
      ],
    });
    const advanced = await maybeAdvanceParentTeamWaitCursor(
      parentPath,
      'wait-step'
    );
    expect(advanced).toBe(false);
    const parent = await stateRead(parentPath);
    expect(parent.cursor).toBe(1);
  });

  it('skips advance when parent at unexpected cursor (EC-2)', async () => {
    const parentPath = await makeParent({
      cursor: 0, // sitting on team-create-step, NOT team-wait
      teammates: [
        { name: 'a', agent_id: 'a@team-x', status: 'completed' },
      ],
    });
    const advanced = await maybeAdvanceParentTeamWaitCursor(
      parentPath,
      'wait-step'
    );
    expect(advanced).toBe(false);
    const parent = await stateRead(parentPath);
    expect(parent.cursor).toBe(0);
  });

  it('advances past skipped sibling steps', async () => { // FR-002
    const parentPath = await makeParent({
      cursor: 1,
      steps: [
        { id: 'tc', type: 'team-create' },
        { id: 'wait-step', type: 'team-wait' },
        { id: 'cond', type: 'command' },
        { id: 'after', type: 'command' },
      ],
      teammates: [{ name: 'a', agent_id: 'a@team-x', status: 'completed' }],
    });
    // Mark step 2 as skipped before advancing.
    const parent = await stateRead(parentPath);
    parent.steps[2].status = 'skipped';
    await stateWrite(parentPath, parent);

    await maybeAdvanceParentTeamWaitCursor(parentPath, 'wait-step');
    const advanced = await stateRead(parentPath);
    expect(advanced.cursor).toBe(3);
  });
});

// FR-001 + FR-002 + FR-009: archiveWorkflow integration
describe('archiveWorkflow (FR-001, FR-002, FR-009)', () => {
  it('renames child to history/success/ and updates parent slot', async () => { // AC US1.1
    const parentPath = await makeParent({
      cursor: 1,
      teammates: [
        { name: 'worker-0', agent_id: 'worker-0@team-x', status: 'running' },
        { name: 'worker-1', agent_id: 'worker-1@team-x', status: 'running' },
      ],
    });
    const childPath = await makeChild({
      name: 'worker-0',
      parentPath,
      alternateAgentId: 'worker-0@team-x',
      status: 'completed',
    });
    const archivePath = await archiveWorkflow(childPath, 'success');
    expect(archivePath).toMatch(/\.wheel\/history\/success\/.*\.json$/);

    // Child state file moved.
    await expect(fs.access(childPath)).rejects.toThrow();
    // Archive exists at returned path.
    await fs.access(archivePath);

    // Parent slot flipped.
    const parent = await stateRead(parentPath);
    expect(parent.teams['wait-step'].teammates['worker-0@team-x'].status).toBe(
      'completed'
    );
    // Cursor stays at 1 (other teammate still running).
    expect(parent.cursor).toBe(1);
  });

  it('all-done last archive triggers cursor advance', async () => { // AC US1.1
    const parentPath = await makeParent({
      cursor: 1,
      teammates: [
        { name: 'w-0', agent_id: 'w-0@team-x', status: 'completed' },
        { name: 'w-1', agent_id: 'w-1@team-x', status: 'running' },
      ],
    });
    const childPath = await makeChild({
      name: 'w-1',
      parentPath,
      alternateAgentId: 'w-1@team-x',
      status: 'completed',
    });
    await archiveWorkflow(childPath, 'success');
    const parent = await stateRead(parentPath);
    expect(parent.cursor).toBe(2);
    expect(parent.steps[1].status).toBe('done');
  });

  it('failure bucket maps to status: failed (FR-006)', async () => {
    const parentPath = await makeParent({
      teammates: [
        { name: 'w-0', agent_id: 'w-0@team-x', status: 'running' },
      ],
    });
    const childPath = await makeChild({
      name: 'w-0',
      parentPath,
      alternateAgentId: 'w-0@team-x',
      status: 'failed',
    });
    await archiveWorkflow(childPath, 'failure');
    const parent = await stateRead(parentPath);
    expect(parent.teams['wait-step'].teammates['w-0@team-x'].status).toBe(
      'failed'
    );
  });

  it('missing parent state file logs warning, no throw (EC-1)', async () => {
    const childPath = await makeChild({
      name: 'orphan',
      parentPath: path.join(activeDir, '.wheel', 'state_does_not_exist.json'),
      alternateAgentId: 'orphan@team-x',
    });
    const archivePath = await archiveWorkflow(childPath, 'success');
    expect(archivePath).toMatch(/\.wheel\/history\/success\//);
    await fs.access(archivePath);
  });

  it('child without parent_workflow archives without parent update (FR-009)', async () => {
    const childPath = await makeChild({
      name: 'standalone',
      parentPath: null,
    });
    const archivePath = await archiveWorkflow(childPath, 'success');
    await fs.access(archivePath);
  });

  it('concurrent archives both update parent slots (FR-007 + EC-3)', async () => {
    const parentPath = await makeParent({
      cursor: 1,
      teammates: [
        { name: 'w-a', agent_id: 'w-a@team-x', status: 'running' },
        { name: 'w-b', agent_id: 'w-b@team-x', status: 'running' },
      ],
    });
    const childA = await makeChild({
      name: 'w-a',
      parentPath,
      alternateAgentId: 'w-a@team-x',
      status: 'completed',
    });
    const childB = await makeChild({
      name: 'w-b',
      parentPath,
      alternateAgentId: 'w-b@team-x',
      status: 'completed',
    });
    // Concurrent archives — both updates should land.
    await Promise.all([
      archiveWorkflow(childA, 'success'),
      archiveWorkflow(childB, 'success'),
    ]);
    const parent = await stateRead(parentPath);
    expect(parent.teams['wait-step'].teammates['w-a@team-x'].status).toBe(
      'completed'
    );
    expect(parent.teams['wait-step'].teammates['w-b@team-x'].status).toBe(
      'completed'
    );
    // Cursor advanced because both teammates terminal.
    expect(parent.cursor).toBe(2);
  });
});

// FR-008: log emission
describe('archive_parent_update logging (FR-008)', () => {
  it('emits archive_parent_update entry with cursor_advanced flag', async () => {
    const parentPath = await makeParent({
      teammates: [
        { name: 'w-0', agent_id: 'w-0@team-x', status: 'running' },
      ],
    });
    const childPath = await makeChild({
      name: 'w-0',
      parentPath,
      alternateAgentId: 'w-0@team-x',
      status: 'completed',
    });
    await archiveWorkflow(childPath, 'success');
    const log = await fs.readFile(
      path.join(activeDir, '.wheel', 'wheel.log'),
      'utf-8'
    );
    expect(log).toContain('archive_parent_update');
    expect(log).toContain('child_agent_id=w-0@team-x');
    expect(log).toContain('cursor_advanced=true');
  });
});
