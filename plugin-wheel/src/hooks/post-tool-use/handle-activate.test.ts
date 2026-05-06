// Tests for handleActivation's alt_agent_id resolution.
//
// Architectural fix: when an activate.sh command lacks the legacy
// `--as <id>` flag, fall back to `hookInput.agent_id` (the spawned
// sub-agent's intrinsic identity from Claude Code). This decouples
// parent-child linkage from prompt-string fidelity — if the
// orchestrator paraphrases the spawn prompt and drops --as, the link
// still works because the wheel reads the alt_id from the sub-agent's
// own session metadata.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { handleActivation } from './handle-activate.js';
import { stateRead } from '../../shared/state.js';

const TEST_ROOT = '/tmp/wheel-handle-activate-test';
let testCounter = 0;
let activeDir: string;

beforeEach(async () => {
  testCounter++;
  activeDir = path.join(TEST_ROOT, `t-${testCounter}-${Date.now()}`);
  await fs.mkdir(activeDir, { recursive: true });
  process.chdir(activeDir);
  await fs.mkdir('.wheel', { recursive: true });
  // Minimal workflow file so resolveWorkflowFile + loadWorkflowJson succeed.
  await fs.mkdir('workflows', { recursive: true });
  await fs.writeFile(
    'workflows/dummy.json',
    JSON.stringify({ name: 'dummy-wf', version: '1.0.0', steps: [{ id: 's1', type: 'command' }] }),
  );
});

afterEach(async () => {
  process.chdir('/tmp');
  await fs.rm(activeDir, { recursive: true, force: true });
});

describe('handleActivation alt_agent_id resolution', () => {
  it('uses hookInput.agent_id as alt_id when --as is absent and agent_id has @<team>', async () => {
    // Spawned sub-agent: no --as in command, but Claude Code populates
    // hookInput.agent_id with the canonical `<short>@<team>` form.
    const activateLine = 'bash plugin-wheel/bin/activate.sh dummy';
    const hookInput = {
      session_id: 'sub-session-1',
      agent_id: 'worker-1@test-team',
    };
    const { activated } = await handleActivation(activateLine, hookInput);
    expect(activated).toBe(true);

    // The new state file should carry alternate_agent_id from
    // hookInput.agent_id since --as was absent.
    const files = (await fs.readdir('.wheel')).filter(f => f.startsWith('state_'));
    expect(files.length).toBe(1);
    const state = await stateRead(`.wheel/${files[0]}`);
    expect(state.alternate_agent_id).toBe('worker-1@test-team');
  });

  it('--as in command takes priority over hookInput.agent_id', async () => {
    // Both sources present; --as wins (legacy contract preserved).
    const activateLine = 'bash plugin-wheel/bin/activate.sh dummy --as legacy@team';
    const hookInput = {
      session_id: 'sub-session-2',
      agent_id: 'fallback@team',
    };
    const { activated } = await handleActivation(activateLine, hookInput);
    expect(activated).toBe(true);

    const files = (await fs.readdir('.wheel')).filter(f => f.startsWith('state_'));
    const state = await stateRead(`.wheel/${files[0]}`);
    expect(state.alternate_agent_id).toBe('legacy@team');
  });

  it('does NOT use hookInput.agent_id as alt_id when it lacks @<team> (top-level run, not teammate)', async () => {
    // Top-level wheel run: agent_id is a bare session-level id without
    // `@`. Stamping it as alt_id would mis-link to a parent slot.
    const activateLine = 'bash plugin-wheel/bin/activate.sh dummy';
    const hookInput = {
      session_id: 'top-session',
      agent_id: 'plain-session-agent',
    };
    const { activated } = await handleActivation(activateLine, hookInput);
    expect(activated).toBe(true);

    const files = (await fs.readdir('.wheel')).filter(f => f.startsWith('state_'));
    const state = await stateRead(`.wheel/${files[0]}`);
    // alt_id should NOT be set (or set to falsy) — top-level run has
    // no parent slot to link to.
    expect(state.alternate_agent_id ?? '').toBe('');
  });
});
