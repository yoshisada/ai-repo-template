// Tests for the post-fix dispatchTeamWait progress + wake-up + child-step
// auto-advance logic (bugs #16, #19, #21 from the parity-completion PR).
//
// All paths are exercised through the public dispatchStep entry point;
// the helpers in dispatch-team.ts are wrapped by `_teamWaitStopBlock`
// and `_teamWaitTeammateIdle` inside dispatch.ts.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit, stateAddTeammate, stateSetStepStatus } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-team-wait-progress-test';
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

async function setupParentWithTeammates(slots: Array<{ id: string; status: string }>): Promise<string> {
  const stateFile = '.wheel/state_parent.json';
  await stateInit({
    stateFile,
    workflow: {
      name: 'parent', version: '1.0',
      steps: [
        { id: 'create', type: 'team-create', team_name: 'tt' },
        { id: 't1', type: 'teammate', team: 'create', workflow: 'sub' },
        { id: 'wait', type: 'team-wait', team: 'create' },
      ],
    },
    sessionId: 'sess',
    agentId: 'parent',
  });
  const state = await stateRead(stateFile);
  state.teams['create'] = { team_name: 'tt', teammates: {}, created_at: new Date().toISOString() };
  await stateWrite(stateFile, state);
  for (const s of slots) {
    await stateAddTeammate(stateFile, 'create', {
      task_id: '', status: s.status as any, agent_id: `${s.id}@tt`,
      output_dir: `.wheel/outputs/${s.id}`, assign: {},
      started_at: null, completed_at: null,
    });
  }
  await stateSetStepStatus(stateFile, 2, 'working'); // wait-all working
  const fresh = await stateRead(stateFile);
  fresh.cursor = 2;
  await stateWrite(stateFile, fresh);
  return stateFile;
}

async function writeChildStateFile(opts: {
  filename: string;
  alternateAgentId: string;
  cursor: number;
  step: { id: string; type: string; status: string; instruction?: string; output?: string };
  parent: string;
}): Promise<string> {
  const stateFile = `.wheel/${opts.filename}`;
  const state = {
    workflow_name: 'sub',
    workflow_version: '1.0',
    workflow_file: 'sub.json',
    workflow_definition: {
      name: 'sub',
      version: '1.0',
      steps: [{ ...opts.step }],
    },
    cursor: opts.cursor,
    steps: [{ id: opts.step.id, type: opts.step.type, status: opts.step.status }],
    teams: {},
    status: 'running',
    started_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    owner_session_id: 'sub-sess',
    owner_agent_id: '',
    alternate_agent_id: opts.alternateAgentId,
    parent_workflow: opts.parent,
    session_registry: {},
  };
  await fs.writeFile(stateFile, JSON.stringify(state, null, 2));
  return stateFile;
}

describe('dispatchTeamWait stop branch — progress visibility (bug #21)', () => {
  it('emits a Progress: snapshot block with per-slot details when not all teammates terminal', async () => {
    const stateFile = await setupParentWithTeammates([
      { id: 'w1', status: 'pending' },
      { id: 'w2', status: 'completed' },
    ]);
    const result = await dispatchStep(
      { id: 'wait', type: 'team-wait', team: 'create' } as any,
      'stop', {}, stateFile, 2,
    );
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('Progress: 1/2 completed');
    expect(result.additionalContext).toContain('slot "w1@tt"');
    expect(result.additionalContext).toContain('slot "w2@tt"');
  });

  it('block message includes anti-wheel-stop guidance when no pending slots needing re-spawn', async () => {
    const stateFile = await setupParentWithTeammates([
      { id: 'w1', status: 'running' },
    ]);
    const result = await dispatchStep(
      { id: 'wait', type: 'team-wait', team: 'create' } as any,
      'stop', {}, stateFile, 2,
    );
    expect(result.decision).toBe('block');
    // Anti-wheel-stop guidance — orchestrator must not bail on the
    // workflow during routine wait gaps.
    expect(result.additionalContext).toContain('Wheel-stop is reserved');
    expect(result.additionalContext).toContain('Silence between turns is normal');
    // Anti-spam-action guidance: don't re-spawn or re-read sentinel,
    // but DO allow targeted SendMessage to stuck workers.
    expect(result.additionalContext).toContain('Do NOT');
    expect(result.additionalContext).toContain('SendMessage');
  });
});

describe('dispatchTeamWait teammate_idle — wake-up branch (bug #16)', () => {
  it('emits SendMessage block when child is at agent step pending', async () => {
    const stateFile = await setupParentWithTeammates([
      { id: 'w1', status: 'running' },
    ]);
    await writeChildStateFile({
      filename: 'state_child.json',
      alternateAgentId: 'w1@tt',
      cursor: 0,
      step: {
        id: 'do-work', type: 'agent', status: 'pending',
        instruction: 'Write a haiku', output: '.wheel/outputs/haiku.md',
      },
      parent: stateFile,
    });
    const result = await dispatchStep(
      { id: 'wait', type: 'team-wait', team: 'create' } as any,
      'teammate_idle',
      { teammate_name: 'w1', team_name: 'tt' },
      stateFile, 2,
    );
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('SendMessage({');
    // The SendMessage `to:` field uses the short teammate_name (`w1`) — the
    // recipient address the harness uses. The full agent_id (`w1@tt`) is
    // the parent-slot join key, not the message recipient.
    expect(result.additionalContext).toContain('to: "w1"');
    expect(result.additionalContext).toContain('do-work');
  });

  it('returns approve and advances child when child is at command step pending (bug #19)', async () => {
    const stateFile = await setupParentWithTeammates([
      { id: 'w1', status: 'running' },
    ]);
    // Use stateInit for the child so its state.steps shape is fully
    // compatible with dispatchCommand (command_log etc).
    const childFile = '.wheel/state_child.json';
    await stateInit({
      stateFile: childFile,
      workflow: {
        name: 'sub', version: '1.0',
        steps: [{ id: 'finish', type: 'command', command: 'echo done' } as any],
      },
      sessionId: 'sub-sess',
      agentId: '',
    });
    const cs = await stateRead(childFile);
    (cs as any).alternate_agent_id = 'w1@tt';
    (cs as any).parent_workflow = stateFile;
    cs.cursor = 0;
    await stateWrite(childFile, cs);

    const result = await dispatchStep(
      { id: 'wait', type: 'team-wait', team: 'create' } as any,
      'teammate_idle',
      { teammate_name: 'w1', team_name: 'tt' },
      stateFile, 2,
    );
    expect(result.decision).toBe('approve');
    // Child should have either advanced past cursor 0 OR archived. Both
    // outcomes mean bug #19 fired and ran the command.
    let advanced = false;
    try {
      const fresh = await stateRead(childFile);
      if (fresh.steps[0].status === 'done' || fresh.cursor > 0) advanced = true;
    } catch {
      advanced = true; // archive removed the file → also counts
    }
    expect(advanced).toBe(true);
  });

  it('returns approve when child state file does not exist', async () => {
    const stateFile = await setupParentWithTeammates([
      { id: 'w1', status: 'running' },
    ]);
    // No child file written — orphan teammate.
    const result = await dispatchStep(
      { id: 'wait', type: 'team-wait', team: 'create' } as any,
      'teammate_idle',
      { teammate_name: 'w1', team_name: 'tt' },
      stateFile, 2,
    );
    expect(result.decision).toBe('approve');
  });
});

describe('dispatchTeamWait stop branch — pending-slot re-emit (bug #8)', () => {
  it('re-emits the spawn block when all slots are pending (orchestrator never acted on first emit)', async () => {
    const stateFile = await setupParentWithTeammates([
      { id: 'w1', status: 'pending' },
      { id: 'w2', status: 'pending' },
    ]);
    const result = await dispatchStep(
      { id: 'wait', type: 'team-wait', team: 'create' } as any,
      'stop', {}, stateFile, 2,
    );
    expect(result.decision).toBe('block');
    // Should include both progress AND spawn instructions.
    expect(result.additionalContext).toContain('Progress: 0/2 completed');
    expect(result.additionalContext).toContain('parallel Agent tool call');
    expect(result.additionalContext).toContain('--as w1@tt');
    expect(result.additionalContext).toContain('--as w2@tt');
  });
});
