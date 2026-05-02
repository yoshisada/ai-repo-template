// FR-008 A1 — handleDeactivate parity tests.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { handleDeactivate } from './post-tool-use.js';

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
