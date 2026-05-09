// FR-006 A2-A4 — dispatchTeammate parity tests.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-teammate-test';

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

describe('dispatchTeammate FR-006 parity', () => {
  // FR-006 A2
  it('writes context.json + assignment.json into teammate output_dir', async () => {
    const statePath = path.join(TEST_DIR, 'ctx.json');
    const step = {
      id: 's1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
      assign: { task: 'do' },
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'tm');

    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    const outputDir = `.wheel/outputs/team-tm/${step.id}`;
    const ctxPath = path.join(outputDir, 'context.json');
    const assignPath = path.join(outputDir, 'assignment.json');
    const ctxStat = await fs.stat(ctxPath);
    const assignStat = await fs.stat(assignPath);
    expect(ctxStat.isFile()).toBe(true);
    expect(assignStat.isFile()).toBe(true);
    const assignData = JSON.parse(await fs.readFile(assignPath, 'utf-8'));
    expect(assignData).toEqual({ task: 'do' });

    // cleanup
    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });

  // FR-006 A3
  it('_teammateChainNext: emits a single batched block, not one per teammate', async () => {
    const statePath = path.join(TEST_DIR, 'chain.json');
    const step = {
      id: 's1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
      assign: { task: 'a' },
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'tm');

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);

    expect(result.decision).toBe('block');
    // Post-fix: spawn block emits literal `Agent({...})` tool-call JSON
    // (one block per teammate) so the orchestrator can copy-paste
    // verbatim. The bracketing wording changed from "Spawn N teammate"
    // (shell parity) to "Make these N parallel Agent tool calls" — the
    // INTENT is the same (one batched message with N spawns).
    expect(result.additionalContext).toContain('parallel Agent tool call');
    expect(result.additionalContext).toContain('s1');
    expect(result.additionalContext).toContain('--as');

    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });

  // Architectural fix — the emitted spawn block uses the SHORT name
  // (without `@<team>` suffix) as the Agent call's `name` parameter.
  //
  // Why short name: Claude Code mangles `name + team_name` into the
  // spawned sub-agent's `agent_id`. With `name="w1"` + `team_name="tm"`,
  // the spawned agent_id is `w1@tm` — verbatim equal to the slot's
  // registered agent_id. The sub-agent's intrinsic hookInput.agent_id
  // then matches the slot during handleActivation, so the parent-link
  // works without depending on `--as` surviving prompt paraphrasing.
  //
  // Sending the FULL agent_id as `name` instead would mangle: Claude
  // Code strips `@` from name, producing `w1-tm@tm` (a different,
  // non-matching key). That's why short-name is the right contract.
  it('spawn block uses short-name as Agent.name (matches slot agent_id under Claude Code mangling)', async () => {
    const statePath = path.join(TEST_DIR, 'name-shortname.json');
    const step = {
      id: 'w1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
      assign: { task: 'a' },
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'tm');

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('name: "w1",');
    expect(result.additionalContext).not.toContain('name: "w1@tm"');
    expect(result.additionalContext).toContain('team_name: "tm"');

    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });

  // Per-slot model: when the `teammate` step JSON sets `model`, the
  // emitted spawn block carries `model: "<value>"` so each spawned
  // sub-agent runs on the requested model instead of inheriting the
  // parent orchestrator's. Omitted → spawn block has no `model:` line.
  it('per-slot model field templates into the emitted Agent spawn block', async () => {
    const statePath = path.join(TEST_DIR, 'model.json');
    const step = {
      id: 's1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
      assign: { task: 'a' },
      model: 'haiku',
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'tm');

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
    expect(result.decision).toBe('block');
    expect(result.additionalContext).toContain('model: "haiku"');

    // Slot is persisted with the model field.
    const stateAfter = await stateRead(statePath);
    const slot = stateAfter.teams.main.teammates['s1@tm'];
    expect(slot.model).toBe('haiku');

    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });

  it('omits model line when teammate step has no model field', async () => {
    const statePath = path.join(TEST_DIR, 'no-model.json');
    const step = {
      id: 's1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
      assign: { task: 'a' },
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'tm');

    const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
    expect(result.decision).toBe('block');
    expect(result.additionalContext).not.toContain('model:');

    const stateAfter = await stateRead(statePath);
    const slot = stateAfter.teams.main.teammates['s1@tm'];
    expect(slot.model).toBeUndefined();

    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });

  // Idea 5: spawn block pre-loads the worker with the sub-workflow's
  // first agent step's instruction + output path, so the worker can
  // act on the first turn without waiting for hook interpretation.
  it('spawn block pre-loads first agent step instructions when sub-workflow JSON exists on disk', async () => {
    // Write a fake sub-workflow JSON at workflows/sub-pre.json with an
    // agent step. The resolver looks for the workflow via its name.
    const cwd = process.cwd();
    const tmpRoot = path.join(TEST_DIR, 'preload-cwd');
    await fs.mkdir(path.join(tmpRoot, 'workflows'), { recursive: true });
    await fs.writeFile(
      path.join(tmpRoot, 'workflows', 'sub-pre.json'),
      JSON.stringify({
        name: 'sub-pre', version: '1.0',
        steps: [
          { id: 'do-x', type: 'agent', instruction: 'Pretend to do X.', output: '.wheel/outputs/x.txt' },
        ],
      }),
    );
    process.chdir(tmpRoot);
    try {
      const statePath = path.join(tmpRoot, 'state.json');
      const step = {
        id: 's1',
        type: 'teammate',
        team: 'main',
        workflow: 'sub-pre',
        assign: {},
      };
      await stateInit({
        stateFile: statePath,
        workflow: { name: 'wf', version: '1.0', steps: [step as any] },
        sessionId: 's',
        agentId: '',
      });
      await setupTeam(statePath, 'main', 'tm');

      const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
      expect(result.decision).toBe('block');
      // The poll-every-turn spawn template includes the first agent
      // step's output path in a single line ("On turn 2 you'll typically
      // need to write content to <path>"). The full ceremony detail
      // lives in the wheel's per-park sentinel; the spawn-template just
      // hints at it. Verify the path made it through.
      expect(result.additionalContext).toContain('.wheel/outputs/x.txt');
    } finally {
      process.chdir(cwd);
    }
  });

  it('spawn block falls back to generic prompt when sub-workflow has no agent step', async () => {
    // Sub-workflow with only command steps (no agent) — pre-load is null.
    const cwd = process.cwd();
    const tmpRoot = path.join(TEST_DIR, 'preload-noagent');
    await fs.mkdir(path.join(tmpRoot, 'workflows'), { recursive: true });
    await fs.writeFile(
      path.join(tmpRoot, 'workflows', 'sub-cmd.json'),
      JSON.stringify({
        name: 'sub-cmd', version: '1.0',
        steps: [{ id: 'cmd', type: 'command', command: 'echo hi' }],
      }),
    );
    process.chdir(tmpRoot);
    try {
      const statePath = path.join(tmpRoot, 'state.json');
      const step = {
        id: 's1', type: 'teammate', team: 'main',
        workflow: 'sub-cmd', assign: {},
      };
      await stateInit({
        stateFile: statePath,
        workflow: { name: 'wf', version: '1.0', steps: [step as any] },
        sessionId: 's', agentId: '',
      });
      await setupTeam(statePath, 'main', 'tm');

      const result = await dispatchStep(step as any, 'stop', {}, statePath, 0);
      expect(result.decision).toBe('block');
      // No first-step output-path hint when there's no agent step.
      expect(result.additionalContext).not.toContain('On turn 2 you\'ll typically need to write');
    } finally {
      process.chdir(cwd);
    }
  });

  // FR-006 A4
  it('post_tool_use TaskCreate detection updates teammate task_id', async () => {
    const statePath = path.join(TEST_DIR, 'tc.json');
    const step = {
      id: 's1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [step as any] },
      sessionId: 's',
      agentId: '',
    });
    await setupTeam(statePath, 'main', 'tm');

    // First, dispatch stop to register teammate s1.
    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    // Now simulate orchestrator calling TaskCreate with subject matching s1.
    await dispatchStep(
      step as any,
      'post_tool_use',
      {
        tool_name: 'TaskCreate',
        tool_input: { subject: 's1', task_id: 'task-abc' },
      },
      statePath,
      0,
    );

    const finalState = await stateRead(statePath);
    // Post-fix: teammate slots are keyed by `name@team_name`, not the
    // short step id. teammateMatchTaskCreate matches by substring inside
    // the slot key, so subject="s1" still resolves to slot "s1@tm".
    expect(finalState.teams.main.teammates['s1@tm'].task_id).toBe('task-abc');

    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });

  // FR-006 A4 (additional)
  it('dynamic-spawn loop threads agent_assign distribution', async () => {
    // Build a loop_from output containing 4 items; max_agents=2 → round-robin.
    const itemsFile = path.join(TEST_DIR, 'items.json');
    await fs.writeFile(itemsFile, JSON.stringify(['a', 'b', 'c', 'd']));

    const statePath = path.join(TEST_DIR, 'dyn.json');
    const items_step = { id: 'items', type: 'command' };
    const step = {
      id: 's1',
      type: 'teammate',
      team: 'main',
      workflow: 'sub',
      loop_from: 'items',
      max_agents: 2,
      name: 'worker',
    };
    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [items_step as any, step as any] },
      sessionId: 's',
      agentId: '',
    });
    // Write items output into state.
    {
      const s = await stateRead(statePath);
      s.steps[0].output = itemsFile;
      s.teams.main = { team_name: 'tm', teammates: {} };
      await stateWrite(statePath, s);
    }

    await dispatchStep(step as any, 'stop', {}, statePath, 1);

    const finalState = await stateRead(statePath);
    const tm = finalState.teams.main.teammates;
    expect(Object.keys(tm).length).toBe(2);
    // Post-fix: teammate map is keyed by `name@team_name` (the agent_id),
    // not by the short name. This matches the join key used in
    // `stateUpdateParentTeammateSlot` (parent slot lookup by
    // child.alternate_agent_id) — keeping a separate short-name key
    // would split the source-of-truth.
    // Round-robin: bucket 0 = ['a', 'c'], bucket 1 = ['b', 'd']
    expect((tm['worker-0@tm'].assign as any).items).toEqual(['a', 'c']);
    expect((tm['worker-1@tm'].assign as any).items).toEqual(['b', 'd']);

    await fs.rm('.wheel/outputs/team-tm', { recursive: true, force: true });
  });
});
