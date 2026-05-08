// Tests for runArchiveFinalizers — the always-run cleanup contract
// that wipes ~/.claude/teams/<name>/ for every team-create step in
// the workflow definition, regardless of which archive path
// (success/failure/stopped) we got here through.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import os from 'os';
import path from 'path';
import { runArchiveFinalizers, archiveWorkflow } from './state-archive.js';
import { stateInit } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-archive-finalizer-test';
let testCounter = 0;
let activeDir: string;
let teamsRootBackup: string | null = null;
let fakeTeamsRoot: string;

beforeEach(async () => {
  testCounter++;
  activeDir = path.join(TEST_ROOT, `t-${testCounter}-${Date.now()}`);
  await fs.mkdir(activeDir, { recursive: true });
  process.chdir(activeDir);
  await fs.mkdir('.wheel', { recursive: true });

  // Redirect HOME so runArchiveFinalizers operates on a sandboxed
  // teams dir, not the user's actual ~/.claude/teams/.
  teamsRootBackup = process.env.HOME ?? null;
  process.env.HOME = activeDir;
  fakeTeamsRoot = path.join(activeDir, '.claude', 'teams');
  await fs.mkdir(fakeTeamsRoot, { recursive: true });
});

afterEach(async () => {
  process.chdir('/tmp');
  if (teamsRootBackup !== null) {
    process.env.HOME = teamsRootBackup;
  } else {
    delete process.env.HOME;
  }
  await fs.rm(activeDir, { recursive: true, force: true });
});

function makeState(steps: Array<Record<string, unknown>>): WheelState {
  return {
    workflow_name: 'test-wf',
    workflow_version: '1.0',
    workflow_file: '/tmp/test-wf.json',
    workflow_definition: { name: 'test-wf', version: '1.0', steps: steps as never },
    status: 'completed',
    cursor: steps.length,
    owner_session_id: 'sess',
    owner_agent_id: '',
    parent_workflow: null,
    started_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    steps: steps.map((s) => ({
      id: String(s.id),
      type: String(s.type),
      status: 'done',
      started_at: null,
      completed_at: null,
      output: null,
      command_log: [],
      agents: {},
      loop_iteration: 0,
      awaiting_user_input: false,
      awaiting_user_input_since: null,
      awaiting_user_input_reason: null,
      resolved_inputs: null,
      contract_emitted: false,
    })) as never,
    teams: {},
    session_registry: {},
  } as unknown as WheelState;
}

describe('runArchiveFinalizers — team-config cleanup contract', () => {
  it('removes ~/.claude/teams/<name>/ for each team-create step', async () => {
    const teamA = path.join(fakeTeamsRoot, 'finalizer-test-team-a');
    const teamB = path.join(fakeTeamsRoot, 'finalizer-test-team-b');
    await fs.mkdir(teamA, { recursive: true });
    await fs.mkdir(teamB, { recursive: true });
    await fs.writeFile(path.join(teamA, 'config.json'), '{}');
    await fs.writeFile(path.join(teamB, 'config.json'), '{}');

    const state = makeState([
      { id: 's1', type: 'team-create', team_name: 'finalizer-test-team-a' },
      { id: 's2', type: 'team-create', team_name: 'finalizer-test-team-b' },
      { id: 's3', type: 'team-wait' },
    ]);
    await runArchiveFinalizers(state);

    expect(await fs.access(teamA).then(() => true).catch(() => false)).toBe(false);
    expect(await fs.access(teamB).then(() => true).catch(() => false)).toBe(false);
  });

  it('is a no-op when team dir is already gone (happy path)', async () => {
    const state = makeState([
      { id: 's1', type: 'team-create', team_name: 'never-created-team' },
    ]);
    // Should not throw even though ~/.claude/teams/never-created-team
    // does not exist.
    await expect(runArchiveFinalizers(state)).resolves.toBeUndefined();
  });

  it('skips team_names containing path separators or traversal segments', async () => {
    const sentinelOutside = path.join(activeDir, 'sentinel-outside-teams.txt');
    await fs.writeFile(sentinelOutside, 'must-not-be-deleted');

    const state = makeState([
      { id: 's1', type: 'team-create', team_name: '../../sentinel-outside-teams.txt' },
      { id: 's2', type: 'team-create', team_name: 'foo/bar' },
      { id: 's3', type: 'team-create', team_name: '..' },
      { id: 's4', type: 'team-create', team_name: '.' },
    ]);
    await runArchiveFinalizers(state);

    // Sentinel outside the teams dir must still exist.
    expect(await fs.access(sentinelOutside).then(() => true).catch(() => false)).toBe(true);
  });

  it('ignores non-team-create steps', async () => {
    const state = makeState([
      { id: 's1', type: 'command', team_name: 'should-be-ignored' },
      { id: 's2', type: 'team-wait', team_name: 'also-ignored' },
    ]);
    // Even if a foreign step type carries a team_name field, only
    // team-create steps trigger cleanup. (The validation guard would
    // catch path traversal anyway, but we test the type filter
    // explicitly so future extensions don't accidentally widen the
    // cleanup surface.)
    const dummyDir = path.join(fakeTeamsRoot, 'should-be-ignored');
    await fs.mkdir(dummyDir, { recursive: true });
    await runArchiveFinalizers(state);
    expect(await fs.access(dummyDir).then(() => true).catch(() => false)).toBe(true);
  });

  it('handles workflow with no team-create steps', async () => {
    const state = makeState([
      { id: 's1', type: 'command' },
      { id: 's2', type: 'agent' },
    ]);
    await expect(runArchiveFinalizers(state)).resolves.toBeUndefined();
  });

  it('handles state with no workflow_definition', async () => {
    const state = makeState([{ id: 's1', type: 'team-create', team_name: 'should-not-fire' }]);
    delete (state as unknown as { workflow_definition?: unknown }).workflow_definition;
    const dummyDir = path.join(fakeTeamsRoot, 'should-not-fire');
    await fs.mkdir(dummyDir, { recursive: true });
    await runArchiveFinalizers(state);
    // Without workflow_definition we skip cleanup entirely.
    expect(await fs.access(dummyDir).then(() => true).catch(() => false)).toBe(true);
  });
});

describe('archiveWorkflow integration — finalizer fires on every bucket', () => {
  async function setupArchiveCase(bucket: 'success' | 'failure' | 'stopped'): Promise<{
    stateFile: string;
    teamDir: string;
  }> {
    const teamName = `archive-bucket-${bucket}-team`;
    const teamDir = path.join(fakeTeamsRoot, teamName);
    await fs.mkdir(teamDir, { recursive: true });
    await fs.writeFile(path.join(teamDir, 'config.json'), '{}');

    const stateFile = path.join('.wheel', `state_archive_${bucket}.json`);
    await stateInit({
      stateFile,
      workflow: {
        name: 'archive-test',
        version: '1.0',
        steps: [
          { id: 's1', type: 'team-create', team_name: teamName },
          { id: 's2', type: 'team-wait' },
        ] as never,
      },
      sessionId: 'sess',
      agentId: '',
    });
    // Mark workflow as terminal AND inject workflow_definition (which
    // stateInit leaves null). runArchiveFinalizers reads the team_name
    // values from workflow_definition.steps, so it must be populated
    // for the finalizer to fire.
    const s = await stateRead(stateFile);
    s.status = bucket === 'success' ? 'completed' : 'failed';
    s.cursor = 2;
    s.workflow_definition = {
      name: 'archive-test',
      version: '1.0',
      steps: [
        { id: 's1', type: 'team-create', team_name: teamName },
        { id: 's2', type: 'team-wait' },
      ] as never,
    };
    await stateWrite(stateFile, s);
    return { stateFile, teamDir };
  }

  it('archives to history/success/ AND removes the team dir', async () => {
    const { stateFile, teamDir } = await setupArchiveCase('success');
    await archiveWorkflow(stateFile, 'success');
    expect(await fs.access(teamDir).then(() => true).catch(() => false)).toBe(false);
    const success = await fs.readdir('.wheel/history/success').catch(() => [] as string[]);
    expect(success.length).toBe(1);
  });

  it('archives to history/failure/ AND removes the team dir', async () => {
    const { stateFile, teamDir } = await setupArchiveCase('failure');
    await archiveWorkflow(stateFile, 'failure');
    expect(await fs.access(teamDir).then(() => true).catch(() => false)).toBe(false);
    const failure = await fs.readdir('.wheel/history/failure').catch(() => [] as string[]);
    expect(failure.length).toBe(1);
  });

  it('archives to history/stopped/ AND removes the team dir', async () => {
    const { stateFile, teamDir } = await setupArchiveCase('stopped');
    await archiveWorkflow(stateFile, 'stopped');
    expect(await fs.access(teamDir).then(() => true).catch(() => false)).toBe(false);
    const stopped = await fs.readdir('.wheel/history/stopped').catch(() => [] as string[]);
    expect(stopped.length).toBe(1);
  });
});
