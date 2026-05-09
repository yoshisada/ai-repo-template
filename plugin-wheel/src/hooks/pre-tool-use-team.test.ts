// Tests for the duplicate-spawn guard (Issue F) in pre-tool-use-team.
//
// The guard fires when an Agent call identifies a slot (via either the
// structured `name` field or `--as <agent_id>` in the prompt) AND that
// slot's status is no longer `pending`. Re-spawning a slot that's
// already running/completed/failed produces a duplicate worker that
// can't link back to the parent — wastes orchestrator budget.
//
// Pre-existing guards (team_name mismatch, missing slot identity)
// stay intact; this file focuses on the new duplicate-spawn behavior.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { decideTeamHookOutput } from './pre-tool-use-team.js';
import { stateInit, stateAddTeammate, stateSetTeam, stateUpdateTeammateStatus } from '../lib/state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import type { HookInput } from '../lib/dispatch.js';

const TEST_ROOT = '/tmp/wheel-pre-tool-team-test';
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

async function setupTeammateStep(
  teamName: string,
  slots: Array<{ name: string; status: 'pending' | 'running' | 'completed' | 'failed' }>,
): Promise<{ stateFile: string; sessionId: string }> {
  const stateFile = path.join(activeDir, '.wheel', 'state_p.json');
  const sessionId = 'sess-test';
  await stateInit({
    stateFile,
    workflow: {
      name: 'parent', version: '1.0',
      steps: [
        { id: 'tc', type: 'team-create', team_name: teamName },
        { id: 't1', type: 'teammate', team: 'tc', workflow: 'sub' },
      ] as any,
    },
    sessionId,
    agentId: 'parent-agent',
  });
  // Stub workflow_definition matches steps.
  const cs = await stateRead(stateFile);
  cs.workflow_definition = {
    name: 'parent', version: '1.0',
    steps: [
      { id: 'tc', type: 'team-create', team_name: teamName },
      { id: 't1', type: 'teammate', team: 'tc', workflow: 'sub' },
    ] as any,
  };
  cs.cursor = 1; // teammate step is current.
  cs.steps[1].status = 'working' as any;
  await stateWrite(stateFile, cs);
  await stateSetTeam(stateFile, 'tc', teamName);
  for (const slot of slots) {
    await stateAddTeammate(stateFile, 'tc', {
      task_id: '', status: 'pending',
      agent_id: `${slot.name}@${teamName}`,
      output_dir: `.wheel/outputs/${slot.name}`, assign: {},
      started_at: null, completed_at: null,
    });
    if (slot.status !== 'pending') {
      await stateUpdateTeammateStatus(
        stateFile, 'tc', `${slot.name}@${teamName}`, slot.status,
      );
    }
  }
  return { stateFile, sessionId };
}

function buildAgentInput(opts: {
  name: string;
  teamName: string;
  prompt?: string;
  sessionId: string;
}): HookInput {
  return {
    session_id: opts.sessionId,
    agent_id: 'parent-agent',
    tool_name: 'Agent',
    tool_input: {
      name: opts.name,
      team_name: opts.teamName,
      prompt: opts.prompt ?? 'bash plugin-wheel/bin/activate.sh sub',
    },
  } as unknown as HookInput;
}

describe('pre-tool-use-team duplicate-spawn guard (Issue F)', () => {
  it('blocks Agent call targeting a slot already in status=running', async () => {
    const { sessionId } = await setupTeammateStep('team-x', [
      { name: 'w1', status: 'running' },
    ]);
    const input = buildAgentInput({ name: 'w1', teamName: 'team-x', sessionId });
    const decision = await decideTeamHookOutput(input);
    expect(decision.decision).toBe('block');
    expect(decision.reason).toContain('duplicate-spawn');
    expect(decision.reason).toContain('w1@team-x');
    expect(decision.reason).toContain('running');
    expect(decision.reason).toContain('Wait for hook signals');
  });

  it('blocks Agent call targeting a slot already in status=completed', async () => {
    const { sessionId } = await setupTeammateStep('team-x', [
      { name: 'w1', status: 'completed' },
    ]);
    const input = buildAgentInput({ name: 'w1', teamName: 'team-x', sessionId });
    const decision = await decideTeamHookOutput(input);
    expect(decision.decision).toBe('block');
    expect(decision.reason).toContain('completed');
    expect(decision.reason).toContain('terminated');
  });

  it('blocks Agent call targeting a slot already in status=failed', async () => {
    const { sessionId } = await setupTeammateStep('team-x', [
      { name: 'w1', status: 'failed' },
    ]);
    const input = buildAgentInput({ name: 'w1', teamName: 'team-x', sessionId });
    const decision = await decideTeamHookOutput(input);
    expect(decision.decision).toBe('block');
    expect(decision.reason).toContain('failed');
    expect(decision.reason).toContain('terminated');
  });

  it('passes Agent call targeting a slot still in status=pending (no duplicate)', async () => {
    const { sessionId } = await setupTeammateStep('team-x', [
      { name: 'w1', status: 'pending' },
    ]);
    const input = buildAgentInput({ name: 'w1', teamName: 'team-x', sessionId });
    const decision = await decideTeamHookOutput(input);
    expect(decision.decision).toBeUndefined();
  });

  it('blocks duplicate-spawn detected via --as flag in prompt (Source 2 path)', async () => {
    const { sessionId } = await setupTeammateStep('team-x', [
      { name: 'w1', status: 'running' },
    ]);
    // Agent call with NO `name` field — only --as in the prompt.
    const input = buildAgentInput({
      name: '',
      teamName: 'team-x',
      prompt: 'bash plugin-wheel/bin/activate.sh sub --as w1@team-x',
      sessionId,
    });
    const decision = await decideTeamHookOutput(input);
    expect(decision.decision).toBe('block');
    expect(decision.reason).toContain('duplicate-spawn');
    expect(decision.reason).toContain('w1@team-x');
  });

  it('passes when one slot is running and a DIFFERENT slot is pending and being spawned', async () => {
    const { sessionId } = await setupTeammateStep('team-x', [
      { name: 'w1', status: 'running' },
      { name: 'w2', status: 'pending' },
    ]);
    const input = buildAgentInput({ name: 'w2', teamName: 'team-x', sessionId });
    const decision = await decideTeamHookOutput(input);
    expect(decision.decision).toBeUndefined();
  });
});
