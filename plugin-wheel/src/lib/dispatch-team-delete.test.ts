// FR-006 A7 — dispatchTeamDelete parity tests.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-team-delete-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

async function setupTeam(stateFile: string, teamRef: string, teamName: string) {
  const state = await stateRead(stateFile);
  state.teams[teamRef] = { team_name: teamName, teammates: {} };
  await stateWrite(stateFile, state);
}

describe('dispatchTeamDelete FR-006 A7 parity', () => {
  // (i) stop pending → block "Delete team"
  it('stop hook on pending step blocks with Delete team instruction', async () => {
    const statePath = path.join(TEST_DIR, 'tdel-pending.json');
    const step = { id: 'd1', type: 'team-delete', team: 'main' };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'mainteam');

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('Delete team');
    expect(result.additionalContext).toContain('mainteam');

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0].status).toBe('working');
  });

  // (ii) post_tool_use TeamDelete → state_remove_team + cascade
  it('post_tool_use TeamDelete removes team and advances cursor', async () => {
    const statePath = path.join(TEST_DIR, 'tdel-pt.json');
    const step = { id: 'd1', type: 'team-delete', team: 'main' };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'mainteam');
    {
      const s = await stateRead(statePath);
      s.steps[0].status = 'working';
      await stateWrite(statePath, s);
    }

    await dispatchStep(
      step as any,
      'post_tool_use',
      { tool_name: 'TeamDelete' },
      statePath,
      0,
    );

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0].status).toBe('done');
    expect(finalState.teams.main).toBeUndefined();
  });

  // (iii) idempotency when team already deleted
  it('stop pending with no team is idempotent — marks done and advances', async () => {
    const statePath = path.join(TEST_DIR, 'tdel-idem.json');
    const step = { id: 'd1', type: 'team-delete', team: 'main' };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    // intentionally no setupTeam — team_name is empty.

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
    expect(result.decision).toBe('approve');

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0].status).toBe('done');
  });
});
