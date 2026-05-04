// FR-008 A1 — handleDeactivate parity tests.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { handleDeactivate, handleNormalPath } from './post-tool-use.js';
import { stateInit } from '../lib/state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_ROOT = '/tmp/wheel-hook-deactivate-test';
let activeDir: string;
let counter = 0;

beforeEach(async () => {
  counter++;
  activeDir = path.join(TEST_ROOT, `t-${counter}-${Date.now()}`);
  await fs.mkdir(activeDir, { recursive: true });
  process.chdir(activeDir);
  await fs.mkdir('.wheel', { recursive: true });
});

afterEach(async () => {
  process.chdir('/tmp');
  await fs.rm(activeDir, { recursive: true, force: true });
});

async function writeStateFile(id: string, opts: {
  ownerSession?: string;
  ownerAgent?: string;
  parent?: string | null;
  teams?: any;
} = {}): Promise<string> {
  const sf = path.join('.wheel', `state_${id}.json`);
  await fs.writeFile(sf, JSON.stringify({
    workflow_name: 'wf',
    cursor: 0,
    steps: [],
    owner_session_id: opts.ownerSession ?? '',
    owner_agent_id: opts.ownerAgent ?? '',
    parent_workflow: opts.parent ?? null,
    teams: opts.teams ?? {},
  }));
  return sf;
}

describe('handleDeactivate FR-008 A1 parity', () => {
  it('--all: archives every state file in .wheel/state_*.json', async () => {
    await writeStateFile('a');
    await writeStateFile('b');
    await writeStateFile('c');

    const cmd = '/usr/local/bin/deactivate.sh --all';
    const out = await handleDeactivate(cmd, {});

    expect(out.hookEventName).toBe('PostToolUse');
    const live = (await fs.readdir('.wheel')).filter(f => f.startsWith('state_'));
    expect(live).toEqual([]);
    const stopped = await fs.readdir('.wheel/history/stopped');
    expect(stopped.length).toBe(3);
  });

  it('target-substring: archives state files whose basename contains arg', async () => {
    await writeStateFile('alpha');
    await writeStateFile('beta');
    await writeStateFile('alpha-2');

    const cmd = 'bin/deactivate.sh alpha';
    await handleDeactivate(cmd, {});

    const live = (await fs.readdir('.wheel')).filter(f => f.startsWith('state_'));
    expect(live.sort()).toEqual(['state_beta.json']);
    const stopped = await fs.readdir('.wheel/history/stopped');
    expect(stopped.length).toBe(2);
  });

  it('self-only: matches owner_session_id + owner_agent_id', async () => {
    await writeStateFile('mine', { ownerSession: 's1', ownerAgent: 'a1' });
    await writeStateFile('theirs', { ownerSession: 's2', ownerAgent: 'a2' });

    const cmd = 'deactivate.sh';
    await handleDeactivate(cmd, { session_id: 's1', agent_id: 'a1' });

    const live = (await fs.readdir('.wheel')).filter(f => f.startsWith('state_'));
    expect(live.sort()).toEqual(['state_theirs.json']);
    const stopped = await fs.readdir('.wheel/history/stopped');
    expect(stopped.length).toBe(1);
  });
});

// P1 round-3 regression — handleNormalPath calls maybeArchiveAfterActivation
// after dispatchStep so terminal-cursor workflows archive in the same hook
// fire (parity with handleActivation's pattern).
describe('handleNormalPath archive trigger (P1 round-3)', () => {
  it('terminal agent step archives to history/success/ in same hook fire', async () => {
    // Build a 2-step workflow ending in a terminal:true agent. Pre-advance
    // cursor to the agent step (index 1) and mark it 'working' to simulate
    // the orchestrator having spawned the agent. Place the agent's expected
    // output file. handleNormalPath should dispatch dispatchAgent (stop),
    // which sees the output file, marks step done, advances cursor past
    // the end, and (because terminal:true) sets state.status='completed'.
    // Then the post-dispatch maybeArchiveAfterActivation moves the state
    // file to history/success/.
    //
    // This is the EXACT shape of the agent-chain Phase 2 fixture failure:
    // terminal agent step at end-of-workflow.
    const outFile = path.join(activeDir, 'agent-out.txt');
    await fs.writeFile(outFile, 'agent done');
    const sf = path.join('.wheel', 'state_chain.json');
    const steps = [
      { id: 's1', type: 'command', command: 'true' },
      { id: 's2', type: 'agent', instruction: 'do work', output: outFile, terminal: true },
    ];
    await stateInit({
      stateFile: sf,
      workflow: { name: 'chain', version: '1.0', steps: steps as any },
      sessionId: 's',
      agentId: 'a',
    });
    {
      const s = await stateRead(sf);
      (s as any).workflow_definition = { name: 'chain', version: '1.0', steps };
      s.cursor = 1;
      s.steps[0].status = 'done';
      s.steps[1].status = 'working';
      await stateWrite(sf, s);
    }

    await handleNormalPath({} as any, sf);

    // State file should be archived to history/success/.
    await expect(fs.access(sf)).rejects.toThrow();
    const success = await fs.readdir('.wheel/history/success').catch(() => [] as string[]);
    expect(success.length).toBeGreaterThan(0);
    expect(success.some(f => f.startsWith('chain-'))).toBe(true);
  });

  it('orphan recovery: cursor>=steps.length triggers archive even without dispatch', async () => {
    // Simulate a state file from a pre-fix run: cursor past last index but
    // never archived. Subsequent post_tool_use should archive it.
    const sf = path.join('.wheel', 'state_orphan.json');
    const steps = [
      { id: 's1', type: 'command', command: 'true', terminal: true },
    ];
    await stateInit({
      stateFile: sf,
      workflow: { name: 'orphan', version: '1.0', steps: steps as any },
      sessionId: 's',
      agentId: 'a',
    });
    {
      const s = await stateRead(sf);
      (s as any).workflow_definition = { name: 'orphan', version: '1.0', steps };
      s.cursor = 1; // past last index
      s.steps[0].status = 'done';
      await stateWrite(sf, s);
    }

    await handleNormalPath({} as any, sf);

    // Orphan state file should be archived.
    await expect(fs.access(sf)).rejects.toThrow();
    const success = await fs.readdir('.wheel/history/success').catch(() => [] as string[]);
    expect(success.some(f => f.startsWith('orphan-'))).toBe(true);
  });
});
