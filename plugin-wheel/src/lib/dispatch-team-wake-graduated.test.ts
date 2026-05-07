// Tests for the two-tier wake severity logic in
// `_teamWaitBuildWakeBlock` (Idea 3 from the wake-spam postmortem,
// simplified after smoke testing).
//
// Severity:
//   1-4 idles at same cursor → standard explicit wake instruction
//   5+ idles at same cursor   → escalation hint (stop wake-spamming)
//
// Counter is keyed by child_cursor; cursor advance resets it.
// Wake-spam suppression at the 1-4 tier is handled by emit.ts's
// skip-write-on-no-change (orchestrator detects no change via mtime
// and ends turn without re-acting).
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { _teamWaitBuildWakeBlock } from './dispatch-team-wait-helpers.js';
import { stateInit } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-wake-graduated-test';
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

async function setupChildAtAgentStep(): Promise<{ stateFile: string; childState: WheelState }> {
  const stateFile = path.join(activeDir, '.wheel', 'state_child.json');
  await stateInit({
    stateFile,
    workflow: {
      name: 'sub-wf',
      version: '1.0',
      steps: [
        { id: 'do-work', type: 'agent' },
        { id: 'verify',  type: 'command' },
      ],
    },
    sessionId: 'sub-session',
    agentId: 'worker-1@team-x',
    alternateAgentId: 'worker-1@team-x',
  });
  // Stamp workflow_definition + cursor=0 (do-work agent step) +
  // status=working so wake-block sees a pending agent step.
  const cs = await stateRead(stateFile);
  cs.workflow_definition = {
    name: 'sub-wf',
    version: '1.0',
    steps: [
      {
        id: 'do-work', type: 'agent',
        instruction: 'Write a haiku',
        output: '.wheel/outputs/result.txt',
      },
      { id: 'verify', type: 'command' },
    ],
  };
  cs.cursor = 0;
  cs.steps[0].status = 'working';
  await stateWrite(stateFile, cs);
  return { stateFile, childState: cs };
}

describe('_teamWaitBuildWakeBlock two-tier severity', () => {
  it('1st idle at cursor → standard explicit wake (immediate)', async () => {
    const { stateFile, childState } = await setupChildAtAgentStep();
    const result = await _teamWaitBuildWakeBlock(
      'worker-1@team-x', 'worker-1', 'team-x',
      stateFile, childState,
    );
    expect(result).not.toBeNull();
    expect(result).toContain('SendMessage');
    expect(result).toContain('do-work');
    expect(result).not.toContain('genuinely stuck');

    // Counter should be persisted on the child state.
    const after = await stateRead(stateFile);
    expect((after as any).idle_count_at_cursor).toBe(1);
    expect((after as any).idle_count_cursor).toBe(0);
  });

  it('2nd-4th idle at cursor → still standard wake (counter increments)', async () => {
    const { stateFile } = await setupChildAtAgentStep();
    for (let i = 1; i <= 4; i++) {
      const cs = await stateRead(stateFile);
      const result = await _teamWaitBuildWakeBlock('worker-1@team-x', 'worker-1', 'team-x', stateFile, cs);
      expect(result).not.toBeNull();
      expect(result).toContain('SendMessage');
      expect(result).not.toContain('genuinely stuck');
      const after = await stateRead(stateFile);
      expect((after as any).idle_count_at_cursor).toBe(i);
    }
  });

  it('5th idle at cursor → escalation hint (stop wake-spamming)', async () => {
    const { stateFile } = await setupChildAtAgentStep();
    // Four standard wakes.
    for (let i = 0; i < 4; i++) {
      const cs = await stateRead(stateFile);
      await _teamWaitBuildWakeBlock('worker-1@team-x', 'worker-1', 'team-x', stateFile, cs);
    }
    // Fifth idle — escalation.
    const cs5 = await stateRead(stateFile);
    const result = await _teamWaitBuildWakeBlock('worker-1@team-x', 'worker-1', 'team-x', stateFile, cs5);
    expect(result).not.toBeNull();
    expect(result).toContain('5+ turns');
    expect(result).toContain('genuinely stuck');
    expect(result).toContain('polling backstop');
    expect(result).toContain('Do NOT send another SendMessage');
  });

  it('cursor advance resets the idle counter', async () => {
    const { stateFile } = await setupChildAtAgentStep();
    // Three idles at cursor 0.
    for (let i = 0; i < 3; i++) {
      const cs = await stateRead(stateFile);
      await _teamWaitBuildWakeBlock('worker-1@team-x', 'worker-1', 'team-x', stateFile, cs);
    }
    let after = await stateRead(stateFile);
    expect((after as any).idle_count_at_cursor).toBe(3);

    // Worker progresses → child cursor advances to 1 (verify step is
    // command, not agent — so wake-block returns null because not at
    // an agent step). But to test the counter reset specifically, we
    // simulate cursor=1 with an agent step.
    after.cursor = 1;
    after.workflow_definition!.steps[1] = {
      id: 'verify-agent', type: 'agent',
      instruction: 'Verify the result',
      output: '.wheel/outputs/verified.txt',
    };
    after.steps[1].type = 'agent';
    after.steps[1].status = 'pending';
    await stateWrite(stateFile, after);

    // Idle at cursor 1 — counter resets, this is the 1st idle at cursor 1.
    const cs1 = await stateRead(stateFile);
    const result = await _teamWaitBuildWakeBlock('worker-1@team-x', 'worker-1', 'team-x', stateFile, cs1);
    expect(result).not.toBeNull();
    expect(result).toContain('SendMessage');
    expect(result).not.toContain('genuinely stuck');
    const final = await stateRead(stateFile);
    expect((final as any).idle_count_at_cursor).toBe(1);
    expect((final as any).idle_count_cursor).toBe(1);
  });

  it('returns null when child step is not an agent type', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_cmd-child.json');
    await stateInit({
      stateFile,
      workflow: { name: 'sub', version: '1.0', steps: [{ id: 'cmd', type: 'command' }] },
      sessionId: 's', agentId: 'a',
    });
    const cs = await stateRead(stateFile);
    cs.workflow_definition = {
      name: 'sub', version: '1.0',
      steps: [{ id: 'cmd', type: 'command', command: 'echo hi' }],
    };
    cs.cursor = 0;
    cs.steps[0].status = 'pending';
    await stateWrite(stateFile, cs);
    const result = await _teamWaitBuildWakeBlock('a', 'a', 'team', stateFile, cs);
    expect(result).toBeNull();
  });
});
