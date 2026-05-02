// Tests for FR-003, FR-004, FR-008 (wheel-wait-all-redesign)
// dispatchTeamWait rewrite + _runPollingBackstop integration.
//
// dispatchTeamWait + _runPollingBackstop are exercised through the
// public dispatchStep entry point. _runPollingBackstop is private,
// so we drive it via dispatchStep with hookType='post_tool_use' on a
// team-wait step.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import {
  stateInit,
  stateAddTeammate,
  stateUpdateTeammateStatus,
  stateSetTeam,
  stateSetStepStatus,
} from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-team-wait-test';
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

async function setupParent(opts: {
  teammates: Array<{ name: string; agent_id: string; status?: string }>;
  stepStatus?: 'pending' | 'working';
}): Promise<{ stateFile: string; step: any }> {
  const stateFile = path.join(activeDir, '.wheel', 'state_parent.json');
  await stateInit({
    stateFile,
    workflow: {
      name: 'parent',
      version: '1.0',
      steps: [
        { id: 'tc', type: 'team-create' },
        { id: 'wait', type: 'team-wait' },
      ],
    },
    sessionId: 'sess',
    agentId: 'parent-agent',
  });
  const state = await stateRead(stateFile);
  state.cursor = 1;
  state.workflow_definition = {
    name: 'parent',
    version: '1.0',
    steps: [
      { id: 'tc', type: 'team-create' },
      { id: 'wait', type: 'team-wait', team: 'wait' },
    ],
  };
  await stateWrite(stateFile, state);

  await stateSetTeam(stateFile, 'wait', 'parent-wait');
  for (const t of opts.teammates) {
    await stateAddTeammate(stateFile, 'wait', {
      task_id: '',
      status: 'pending',
      agent_id: t.agent_id,
      output_dir: `.wheel/outputs/${t.name}`,
      assign: {},
      started_at: null,
      completed_at: null,
    });
    if (t.status && t.status !== 'pending') {
      await stateUpdateTeammateStatus(stateFile, 'wait', t.agent_id, t.status as any);
    }
  }

  if (opts.stepStatus) {
    await stateSetStepStatus(stateFile, 1, opts.stepStatus);
  }

  return {
    stateFile,
    step: { id: 'wait', type: 'team-wait', team: 'wait' },
  };
}

async function writeArchive(opts: {
  bucket: 'success' | 'failure' | 'stopped';
  parentStateFile: string;
  alternateAgentId: string;
  workflowName?: string;
}): Promise<void> {
  const archiveDir = path.join(activeDir, '.wheel', 'history', opts.bucket);
  await fs.mkdir(archiveDir, { recursive: true });
  const archive = {
    workflow_name: opts.workflowName ?? 'child-archived',
    parent_workflow: opts.parentStateFile,
    alternate_agent_id: opts.alternateAgentId,
    status: opts.bucket === 'success' ? 'completed' : 'failed',
  };
  await fs.writeFile(
    path.join(archiveDir, `child-${opts.alternateAgentId.replace(/[^a-zA-Z0-9]/g, '_')}.json`),
    JSON.stringify(archive)
  );
}

// FR-003: stop branch — pure re-check
describe('dispatchTeamWait stop branch (FR-003)', () => {
  it('marks step done when all teammates terminal', async () => { // AC US1.1
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'completed' },
        { name: 'b', agent_id: 'b@t', status: 'failed' },
      ],
    });
    await dispatchStep(step, 'stop', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    expect(state.steps[1].status).toBe('done');
  });

  it('keeps step working when teammate still running', async () => { // AC US1.2
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'completed' },
        { name: 'b', agent_id: 'b@t', status: 'running' },
      ],
    });
    await dispatchStep(step, 'stop', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    // pending → working transition still happens.
    expect(state.steps[1].status).toBe('working');
  });

  it('does not mutate teammate slots in stop branch (FR-003)', async () => {
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
    });
    await dispatchStep(
      step,
      'stop',
      { tool_name: 'Agent', tool_input: { name: 'a' } },
      stateFile,
      1
    );
    const state = await stateRead(stateFile);
    expect(state.teams['wait'].teammates['a@t'].status).toBe('running');
  });

  it('handles 0 teammates by marking done immediately', async () => {
    const { stateFile, step } = await setupParent({ teammates: [] });
    await dispatchStep(step, 'stop', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    expect(state.steps[1].status).toBe('done');
  });
});

// FR-003 + FR-004: post_tool_use branch with polling
describe('dispatchTeamWait post_tool_use branch (FR-003, FR-004)', () => {
  it('no-op when live state file present', async () => {
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    // Create a live child state file matching alternate_agent_id.
    const childPath = path.join(activeDir, '.wheel', 'state_child_a.json');
    await stateInit({
      stateFile: childPath,
      workflow: { name: 'child', version: '1.0', steps: [{ id: 's', type: 'command' }] },
      sessionId: 'sess',
      agentId: 'child-a',
      alternateAgentId: 'a@t',
    });
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    expect(state.teams['wait'].teammates['a@t'].status).toBe('running');
    expect(state.steps[1].status).toBe('working');
  });

  it('marks completed when archive in history/success/', async () => { // AC US2.2
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    await writeArchive({
      bucket: 'success',
      parentStateFile: stateFile,
      alternateAgentId: 'a@t',
    });
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    expect(state.teams['wait'].teammates['a@t'].status).toBe('completed');
    // Single teammate, all done → step done.
    expect(state.steps[1].status).toBe('done');
  });

  it('marks failed when archive in history/failure/', async () => { // AC US2.2
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    await writeArchive({
      bucket: 'failure',
      parentStateFile: stateFile,
      alternateAgentId: 'a@t',
    });
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    expect(state.teams['wait'].teammates['a@t'].status).toBe('failed');
  });

  it('marks failed:state-file-disappeared when nothing matches', async () => { // AC US2.1
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    const slot = state.teams['wait'].teammates['a@t'];
    expect(slot.status).toBe('failed');
    expect((slot as any).failure_reason).toBe('state-file-disappeared');
  });

  it('archive evidence wins over orphan default (FR-004 order)', async () => {
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    // No live state file — but failure archive exists, so reconcile via archive.
    await writeArchive({
      bucket: 'failure',
      parentStateFile: stateFile,
      alternateAgentId: 'a@t',
    });
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    const slot = state.teams['wait'].teammates['a@t'];
    expect(slot.status).toBe('failed');
    // The orphan default would have set failure_reason; archive evidence
    // skips that field entirely.
    expect((slot as any).failure_reason).toBeUndefined();
  });

  it('emits wait_all_polling log line with reconciled_count (FR-008)', async () => {
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    await writeArchive({
      bucket: 'success',
      parentStateFile: stateFile,
      alternateAgentId: 'a@t',
    });
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const log = await fs.readFile(
      path.join(activeDir, '.wheel', 'wheel.log'),
      'utf-8'
    );
    expect(log).toContain('wait_all_polling');
    expect(log).toContain('reconciled_count=1');
  });

  it('skips polling when step already done', async () => {
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
    });
    await stateSetStepStatus(stateFile, 1, 'done');
    await dispatchStep(step, 'post_tool_use', {}, stateFile, 1);
    const state = await stateRead(stateFile);
    // Slot stays running because polling skipped.
    expect(state.teams['wait'].teammates['a@t'].status).toBe('running');
  });
});

// FR-005: hook routing remap (delegated test — engineHandleHook owns this)
describe('FR-005 hook remap is engine-layer', () => {
  it('dispatchTeamWait does not respond to teammate_idle directly', async () => {
    const { stateFile, step } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'running' },
      ],
      stepStatus: 'working',
    });
    // teammate_idle hits dispatchTeamWait directly (bypassing engine remap).
    // It should fall through to the default-approve case without mutating
    // any state.
    const result = await dispatchStep(step, 'teammate_idle', {}, stateFile, 1);
    expect(result.decision).toBe('approve');
    const state = await stateRead(stateFile);
    expect(state.teams['wait'].teammates['a@t'].status).toBe('running');
    expect(state.steps[1].status).toBe('working');
  });
});

// FR-006 A5/A6 — _team_wait_complete: summary.json + collect_to copy.
describe('dispatchTeamWait _team_wait_complete (FR-006 A5/A6)', () => {
  it('wait-summary-output: writes summary.json on completion', async () => {
    const { stateFile } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'completed' },
        { name: 'b', agent_id: 'b@t', status: 'failed' },
      ],
    });
    // Override the step.output so _teamWaitComplete writes summary.json there.
    const summaryPath = path.join(activeDir, 'summary-output.json');
    const stepWithOutput = { id: 'wait', type: 'team-wait', team: 'wait', output: summaryPath };

    await dispatchStep(stepWithOutput as any, 'stop', {}, stateFile, 1);

    const summary = JSON.parse(await fs.readFile(summaryPath, 'utf-8'));
    // Teammate slots keyed by agent_id (parent setup uses agent_id as key).
    expect(summary['a@t']).toBeDefined();
    expect(summary['a@t'].status).toBe('completed');
    expect(summary['b@t'].status).toBe('failed');
  });

  it('collect-to-copy: copies teammate output_dir contents into collect_to', async () => {
    const { stateFile } = await setupParent({
      teammates: [
        { name: 'a', agent_id: 'a@t', status: 'completed' },
      ],
    });
    // Seed teammate output_dir with a file to be copied.
    const teamOutputDir = path.join(activeDir, '.wheel', 'outputs', 'a');
    await fs.mkdir(teamOutputDir, { recursive: true });
    await fs.writeFile(path.join(teamOutputDir, 'result.txt'), 'hello');

    // Update teammate's output_dir in state to point to seeded dir.
    {
      const s = await stateRead(stateFile);
      s.teams['wait'].teammates['a@t'].output_dir = teamOutputDir;
      await stateWrite(stateFile, s);
    }

    const collectDir = path.join(activeDir, 'collected');
    const stepWithCollect = {
      id: 'wait', type: 'team-wait', team: 'wait', collect_to: collectDir,
    };

    await dispatchStep(stepWithCollect as any, 'stop', {}, stateFile, 1);

    // Expect <collectDir>/a@t/result.txt to exist with the original content.
    const copied = await fs.readFile(path.join(collectDir, 'a@t', 'result.txt'), 'utf-8');
    expect(copied).toBe('hello');
  });
});
