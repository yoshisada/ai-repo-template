// Tests for the stuck-worker auto-fail path in runPollingBackstop
// (Idea 4 from the wake-spam postmortem).
//
// A live child workflow is "stuck" when:
//   - cursor's step.type === 'agent'
//   - cursor's step.status is 'pending' or 'working'
//   - state.updated_at is older than 5 minutes
//
// The polling backstop marks the parent slot `failed` with reason
// `stuck_worker`. Caps maximum coordination time per fixture.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { runPollingBackstop } from './dispatch-team-polling.js';
import { stateInit, stateAddTeammate, stateSetTeam, stateUpdateTeammateStatus } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-polling-stuck-test';
let testCounter = 0;
let activeDir: string;

beforeEach(async () => {
  testCounter++;
  activeDir = path.join(TEST_ROOT, `t-${testCounter}-${Date.now()}`);
  await fs.mkdir(activeDir, { recursive: true });
  process.chdir(activeDir);
  await fs.mkdir('.wheel', { recursive: true });
});

afterEach(async () => {
  process.chdir('/tmp');
  await fs.rm(activeDir, { recursive: true, force: true });
});

async function setupParentWithRunningTeammate(name: string, agentId: string): Promise<string> {
  const stateFile = path.join(activeDir, '.wheel', 'state_parent.json');
  await stateInit({
    stateFile,
    workflow: {
      name: 'parent', version: '1.0',
      steps: [
        { id: 'tc', type: 'team-create' },
        { id: 'wait', type: 'team-wait' },
      ],
    },
    sessionId: 'parent-sess', agentId: 'parent-agent',
  });
  const state = await stateRead(stateFile);
  state.cursor = 1;
  state.workflow_definition = {
    name: 'parent', version: '1.0',
    steps: [
      { id: 'tc', type: 'team-create' },
      { id: 'wait', type: 'team-wait', team: 'wait' },
    ],
  };
  await stateWrite(stateFile, state);
  await stateSetTeam(stateFile, 'wait', 'team-x');
  await stateAddTeammate(stateFile, 'wait', {
    task_id: '', status: 'pending', agent_id: agentId,
    output_dir: `.wheel/outputs/${name}`, assign: {},
    started_at: null, completed_at: null,
  });
  await stateUpdateTeammateStatus(stateFile, 'wait', agentId, 'running');
  return stateFile;
}

async function writeChildState(opts: {
  filename: string;
  altAgentId: string;
  parent: string;
  cursor: number;
  step: { id: string; type: string; status: string };
  updatedAt: string; // ISO
}): Promise<string> {
  const childFile = path.join(activeDir, '.wheel', opts.filename);
  await stateInit({
    stateFile: childFile,
    workflow: { name: 'sub', version: '1.0', steps: [opts.step] },
    sessionId: 'sub', agentId: '',
    alternateAgentId: opts.altAgentId,
    parentWorkflow: opts.parent,
  });
  // Read, mutate, then DIRECT-WRITE (bypassing stateWrite which re-stamps
  // updated_at). The stuck-worker detection keys off updated_at age.
  const cs = await stateRead(childFile);
  cs.cursor = opts.cursor;
  cs.steps[0] = {
    ...cs.steps[0],
    id: opts.step.id, type: opts.step.type,
    status: opts.step.status as any,
  };
  cs.updated_at = opts.updatedAt;
  await fs.writeFile(childFile, JSON.stringify(cs));
  return childFile;
}

describe('runPollingBackstop stuck-worker detection (Idea 4)', () => {
  it('marks slot failed with reason "stuck_worker" when child is stuck at agent step', async () => {
    const parentFile = await setupParentWithRunningTeammate('w1', 'w1@team-x');
    // Child stuck: agent step, pending, updated_at >5min ago.
    const sixMinutesAgo = new Date(Date.now() - 6 * 60 * 1000).toISOString();
    await writeChildState({
      filename: 'state_child_w1.json',
      altAgentId: 'w1@team-x',
      parent: parentFile,
      cursor: 0,
      step: { id: 'do-work', type: 'agent', status: 'pending' },
      updatedAt: sixMinutesAgo,
    });

    const result = await runPollingBackstop(parentFile, 'wait');
    expect(result.reconciledCount).toBe(1);
    expect(result.stillRunningCount).toBe(0);

    const after = await stateRead(parentFile);
    const slot = after.teams.wait.teammates['w1@team-x'];
    expect(slot.status).toBe('failed');
    expect((slot as any).failure_reason).toBe('stuck_worker');
  });

  it('does NOT mark slot failed when child is recently updated (not stuck)', async () => {
    const parentFile = await setupParentWithRunningTeammate('w1', 'w1@team-x');
    // Child fresh: agent step, working, updated 10 seconds ago.
    const recent = new Date(Date.now() - 10_000).toISOString();
    await writeChildState({
      filename: 'state_child_w1.json',
      altAgentId: 'w1@team-x',
      parent: parentFile,
      cursor: 0,
      step: { id: 'do-work', type: 'agent', status: 'working' },
      updatedAt: recent,
    });

    const result = await runPollingBackstop(parentFile, 'wait');
    expect(result.reconciledCount).toBe(0);
    expect(result.stillRunningCount).toBe(1);

    const after = await stateRead(parentFile);
    expect(after.teams.wait.teammates['w1@team-x'].status).toBe('running');
  });

  it('does NOT mark slot failed when child step is not type=agent', async () => {
    const parentFile = await setupParentWithRunningTeammate('w1', 'w1@team-x');
    // Old updated_at but step type is `command`, not agent — workflows
    // can legitimately sit at a command step waiting for the next
    // dispatcher fire. Stuck detection only triggers on agent steps
    // (where worker action is required).
    const sixMinutesAgo = new Date(Date.now() - 6 * 60 * 1000).toISOString();
    await writeChildState({
      filename: 'state_child_w1.json',
      altAgentId: 'w1@team-x',
      parent: parentFile,
      cursor: 0,
      step: { id: 'cmd', type: 'command', status: 'pending' },
      updatedAt: sixMinutesAgo,
    });

    const result = await runPollingBackstop(parentFile, 'wait');
    expect(result.reconciledCount).toBe(0);
    expect(result.stillRunningCount).toBe(1);
  });

  it('does NOT mark slot failed when child step is already terminal', async () => {
    const parentFile = await setupParentWithRunningTeammate('w1', 'w1@team-x');
    // Old updated_at, but step status='done' — the child has finished
    // its agent step and is between steps. Not stuck, just transient.
    const sixMinutesAgo = new Date(Date.now() - 6 * 60 * 1000).toISOString();
    await writeChildState({
      filename: 'state_child_w1.json',
      altAgentId: 'w1@team-x',
      parent: parentFile,
      cursor: 0,
      step: { id: 'do-work', type: 'agent', status: 'done' },
      updatedAt: sixMinutesAgo,
    });

    const result = await runPollingBackstop(parentFile, 'wait');
    expect(result.reconciledCount).toBe(0);
    // But it'll be marked stillRunning OR get fall-through resolution
    // depending on the bucket scan. We just care it's not stuck-failed.
    const after = await stateRead(parentFile);
    const slot = after.teams.wait.teammates['w1@team-x'];
    if (slot.status === 'failed') {
      expect((slot as any).failure_reason).not.toBe('stuck_worker');
    }
  });
});
