// Scenario: S6 — dispatchStep routes to correct handler
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit, stateAddTeammate } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('dispatchStep', () => {
  it('should return approve for unknown step type', async () => { // FR-007
    const statePath = path.join(TEST_DIR, 'unknown-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'unknown' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'unknown' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should route agent steps to dispatchAgent', async () => { // FR-003
    const statePath = path.join(TEST_DIR, 'agent-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'agent', instruction: 'test' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'agent', instruction: 'do work' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should route command steps to dispatchCommand', async () => { // FR-019
    const statePath = path.join(TEST_DIR, 'command-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo hello' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should skip command execution for non-post_tool_use hooks', async () => { // FR-019
    const statePath = path.join(TEST_DIR, 'non-post-hook.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo test' } as any,
      'session_start',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should route approval steps and return block', async () => { // FR-013 / FR-007 A2
    const statePath = path.join(TEST_DIR, 'approval-step.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'approval' }] },
      sessionId: 's1',
      agentId: '',
    });
    // FR-007 A2 (parity dispatch.sh:1300) — approval blocks on stop hook
    // (and teammate_idle without approval). post_tool_use returns approve.
    const result = await dispatchStep(
      { id: 's1', type: 'approval' } as any,
      'stop',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('block');
  });
});

describe('dispatchAgent', () => {
  it('should set step to working and return context', async () => { // FR-003
    const statePath = path.join(TEST_DIR, 'agent-context.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'agent', instruction: 'do work' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'agent', instruction: 'do work' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
    expect(result.additionalContext).toBeTruthy();
  });
});

describe('dispatchCommand', () => {
  it('should execute command and update state', async () => { // FR-019
    const statePath = path.join(TEST_DIR, 'command-exec.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: 'echo hello' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });
});

describe('dispatchTeammate', () => {
  it('should only respond to stop hook and return approve for post_tool_use', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'teammate-stop-only.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'teammate' }] },
      sessionId: 's1',
      agentId: '',
    });
    // teammate steps only respond to 'stop' — post_tool_use should return approve immediately
    const result = await dispatchStep(
      { id: 's1', type: 'teammate', team: 'main', workflow: 'test' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });

  it('should block with instruction when pending on stop hook', async () => { // FR-006
    const statePath = path.join(TEST_DIR, 'teammate-block.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'teammate' }] },
      sessionId: 's1',
      agentId: '',
    });
    // Add team to state — stateInit initializes teams as {} so we must call stateAddTeammate
    await stateAddTeammate(statePath, 'main', {
      task_id: 't1',
      status: 'pending',
      agent_id: 'worker-1',
      output_dir: '.wheel/outputs/team/test/worker-1',
      assign: { task: 'do work' },
      started_at: null,
      completed_at: null,
    });
    // Set team_name on the team entry (dispatchTeammate requires it)
    const state = await stateRead(statePath);
    state.teams['main'].team_name = 'test-team';
    await stateWrite(statePath, state);

    const result = await dispatchStep(
      { id: 's1', type: 'teammate', team: 'main', workflow: 'test' } as any,
      'stop',
      {},
      statePath,
      0
    );
    // Post-fix: spawn block emits literal `Agent({...})` tool-call JSON
    // (one block per teammate). Wording transitioned from "Spawn the
    // following teammates" → "Make these N parallel Agent tool calls".
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('parallel Agent tool call');
    expect(result.additionalContext).toContain('--as');
  });
});

describe('dispatchBranch', () => {
  it('should return approve for session_start hook', async () => { // FR-017
    const statePath = path.join(TEST_DIR, 'branch-start.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'branch', branches: [] }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'branch', branches: [] } as any,
      'session_start',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });
});

describe('dispatchLoop', () => {
  it('should return approve for session_start hook', async () => { // FR-020
    const statePath = path.join(TEST_DIR, 'loop-start.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'loop', max_iterations: 3 }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'loop', max_iterations: 3 } as any,
      'session_start',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });
});

describe('dispatchTeamCreate', () => {
  it('should return approve for non-stop hooks', async () => { // FR-004
    const statePath = path.join(TEST_DIR, 'team-create-post.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'test', version: '1.0', steps: [{ id: 's1', type: 'team-create', team_name: 'my-team' }] },
      sessionId: 's1',
      agentId: '',
    });
    const result = await dispatchStep(
      { id: 's1', type: 'team-create', team_name: 'my-team' } as any,
      'post_tool_use',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('approve');
  });
});

describe('dispatchTeamWait', () => {
  it('should return block with progress snapshot when teammates not all terminal', async () => {
    // Post-fix: dispatchTeamWait.stop ALWAYS returns block (with progress
    // snapshot) when not done — never silent approve. The snapshot tells
    // the orchestrator what's happening across all child workflows so it
    // can avoid inferring "stuck" from silence.
    const statePath = path.join(TEST_DIR, 'team-wait.json');
    await stateInit({
      stateFile: statePath,
      workflow: {
        name: 'test', version: '1.0', steps: [{ id: 's1', type: 'team-wait', team: 'main' }],
      },
      sessionId: 's1',
      agentId: '',
    });
    // Add a single pending teammate so wait-all has something to report on.
    await stateAddTeammate(statePath, 'main', {
      task_id: '', status: 'pending', agent_id: 'w@t', output_dir: 'o', assign: {},
      started_at: null, completed_at: null,
    });
    const state = await stateRead(statePath);
    state.teams['main'].team_name = 't';
    await stateWrite(statePath, state);

    const result = await dispatchStep(
      { id: 's1', type: 'team-wait', team: 'main' } as any,
      'stop',
      {},
      statePath,
      0
    );
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('Progress:');
    expect(result.additionalContext).toContain('slot "w@t"');
  });
});

// FR-001 — dispatchCommand WORKFLOW_PLUGIN_DIR injection
describe('dispatchCommand: command-exports-plugin-dir', () => {
  it('exports WORKFLOW_PLUGIN_DIR derived from state.workflow_file', async () => {
    // Build a simulated plugin dir tree:
    //   /tmp/wheel-dispatch-test/fakeplugin/workflows/wf.json
    // The derived plugin dir should be the fakeplugin path.
    const pluginRoot = path.join(TEST_DIR, 'fakeplugin');
    const wfDir = path.join(pluginRoot, 'workflows');
    const wfFile = path.join(wfDir, 'wf.json');
    const outFile = path.join(TEST_DIR, 'cmd-out.txt');
    await fs.mkdir(wfDir, { recursive: true });
    await fs.writeFile(wfFile, JSON.stringify({
      name: 'wf', version: '1.0', steps: [{ id: 's1', type: 'command' }],
    }));

    const statePath = path.join(TEST_DIR, 'cmd-plugin-dir.json');
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [{ id: 's1', type: 'command' }] },
      sessionId: 's1',
      agentId: '',
    });
    // Wire workflow_file into state so deriveWorkflowPluginDir can find it.
    {
      const s = await stateRead(statePath);
      s.workflow_file = wfFile;
      await stateWrite(statePath, s);
    }

    // Command echoes WORKFLOW_PLUGIN_DIR to outFile (use printf for portability).
    const cmd = `printf '%s' "$WORKFLOW_PLUGIN_DIR" > ${outFile}`;
    const result = await dispatchStep(
      { id: 's1', type: 'command', command: cmd } as any,
      'post_tool_use',
      {},
      statePath,
      0,
    );
    expect(result.decision).toBe('approve');
    const got = await fs.readFile(outFile, 'utf-8');
    expect(got).toBe(pluginRoot);
  });
});