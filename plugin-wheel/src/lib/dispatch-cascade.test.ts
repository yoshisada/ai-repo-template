// Tests for FR-001 / FR-002 / FR-003 / FR-004 / FR-006 / FR-008 / FR-010
// (wheel-ts-dispatcher-cascade). Validates US-1..US-5 from spec.md.
//
// Test substrate hierarchy: these are TERTIARY (vitest unit) — the primary
// substrate is /kiln:kiln-test wheel <fixture> + /wheel:wheel-test against
// the deployed dist. These cases lock in the behavioral invariants of the
// cascade tail itself.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import { maybeArchiveAfterActivation } from './engine.js';

const TEST_ROOT = '/tmp/wheel-dispatch-cascade-test';
let testCounter = 0;
let activeDir: string;
let originalCwd: string;

beforeEach(async () => {
  testCounter++;
  originalCwd = process.cwd();
  activeDir = path.join(TEST_ROOT, `t-${testCounter}-${Date.now()}`);
  await fs.mkdir(activeDir, { recursive: true });
  // wheel.log + .wheel/history paths are cwd-relative. Each test gets its own dir.
  process.chdir(activeDir);
  await fs.mkdir('.wheel', { recursive: true });
});

afterEach(async () => {
  process.chdir(originalCwd);
  await fs.rm(activeDir, { recursive: true, force: true });
});

// Helper — persist workflow_definition into state (matches what
// handleActivation does in production), then drive the activation cascade.
async function seedWorkflowDef(stateFile: string, steps: any[], name: string): Promise<void> {
  const s = await stateRead(stateFile);
  (s as any).workflow_definition = { name, version: '1.0', steps };
  await stateWrite(stateFile, s);
}

async function runActivationCascade(stateFile: string, firstStep: any): Promise<void> {
  await dispatchStep(firstStep, 'post_tool_use', {}, stateFile, 0, 0);
  await maybeArchiveAfterActivation(stateFile);
}

describe('dispatch cascade (FR-002, US-1)', () => {
  it('cascades through three chained command steps to terminal', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_us1.json');
    const steps = [
      { id: 's1', type: 'command', command: 'true' },
      { id: 's2', type: 'command', command: 'true' },
      { id: 's3', type: 'command', command: 'true' },
    ];
    await stateInit({
      stateFile,
      workflow: { name: 'us1', version: '1.0', steps },
      sessionId: 'sess',
      agentId: 'agent',
    });
    await seedWorkflowDef(stateFile, steps, 'wf');

    await runActivationCascade(stateFile, steps[0]);

    // Original state file archived → no longer at original path.
    const exists = await fs.access(stateFile).then(() => true).catch(() => false);
    expect(exists).toBe(false);

    // Archive bucket should contain the workflow.
    const successDir = path.join('.wheel', 'history', 'success');
    const archived = await fs.readdir(successDir);
    expect(archived.length).toBe(1);

    const archivedState = JSON.parse(
      await fs.readFile(path.join(successDir, archived[0]), 'utf-8')
    );
    expect(archivedState.cursor).toBeGreaterThanOrEqual(3);
    expect(archivedState.steps.every((s: any) => s.status === 'done')).toBe(true);
  });
});

describe('dispatch cascade (FR-002, US-2)', () => {
  it('stops cascade at agent step', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_us2.json');
    const steps = [
      { id: 's1', type: 'command', command: 'true' },
      { id: 's2', type: 'command', command: 'true' },
      { id: 's3', type: 'agent', instruction: 'do work' },
      { id: 's4', type: 'command', command: 'true' },
    ];
    await stateInit({
      stateFile,
      workflow: { name: 'us2', version: '1.0', steps },
      sessionId: 'sess',
      agentId: 'agent',
    });
    await seedWorkflowDef(stateFile, steps, 'wf');

    await runActivationCascade(stateFile, steps[0]);

    // State NOT archived — agent is blocking.
    const stillExists = await fs.access(stateFile).then(() => true).catch(() => false);
    expect(stillExists).toBe(true);

    const state = await stateRead(stateFile);
    expect(state.cursor).toBe(2); // stopped at agent step
    expect(state.steps[0].status).toBe('done');
    expect(state.steps[1].status).toBe('done');
    expect(state.steps[3].status).toBe('pending'); // trailing command not yet run
  });
});

describe('dispatch cascade (FR-008, US-3)', () => {
  it('halts cascade on step failure', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_us3.json');
    const steps = [
      { id: 's1', type: 'command', command: 'true' },
      { id: 's2', type: 'command', command: 'false' }, // exit 1 → fail
      { id: 's3', type: 'command', command: 'true' },
    ];
    await stateInit({
      stateFile,
      workflow: { name: 'us3', version: '1.0', steps },
      sessionId: 'sess',
      agentId: 'agent',
    });
    await seedWorkflowDef(stateFile, steps, 'wf');

    await runActivationCascade(stateFile, steps[0]);

    // State archived to failure bucket.
    const failureDir = path.join('.wheel', 'history', 'failure');
    const archived = await fs.readdir(failureDir).catch(() => [] as string[]);
    expect(archived.length).toBe(1);

    const archivedState = JSON.parse(
      await fs.readFile(path.join(failureDir, archived[0]), 'utf-8')
    );
    expect(archivedState.steps[0].status).toBe('done');
    expect(archivedState.steps[1].status).toBe('failed');
    expect(archivedState.steps[2].status).toBe('pending'); // never dispatched

    // FR-008 halt log line emitted.
    const wheelLog = await fs.readFile(path.join('.wheel', 'wheel.log'), 'utf-8');
    expect(wheelLog).toMatch(/dispatch_cascade_halt.*reason=failed/);
  });
});

describe('dispatch cascade (FR-004)', () => {
  it('cascades to branch target', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_branch.json');
    const steps = [
      { id: 'b1', type: 'branch', condition: 'true', if_zero: 'a', if_nonzero: 'b' },
      { id: 'a', type: 'command', command: 'true' },
      { id: 'b', type: 'command', command: 'true' },
    ];
    await stateInit({
      stateFile,
      workflow: { name: 'branch', version: '1.0', steps },
      sessionId: 'sess',
      agentId: 'agent',
    });
    await seedWorkflowDef(stateFile, steps, 'wf');

    await runActivationCascade(stateFile, steps[0]);

    const successDir = path.join('.wheel', 'history', 'success');
    const archived = await fs.readdir(successDir);
    expect(archived.length).toBe(1);

    const archivedState = JSON.parse(
      await fs.readFile(path.join(successDir, archived[0]), 'utf-8')
    );
    expect(archivedState.steps[0].status).toBe('done'); // branch
    expect(archivedState.steps[1].status).toBe('done'); // target 'a' ran
    expect(archivedState.steps[2].status).toBe('skipped'); // off-target marked skipped
  });
});

describe('dispatch cascade (FR-003)', () => {
  it('cascades after loop completion', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_loop.json');
    const steps = [
      {
        id: 'loop1',
        type: 'loop',
        max_iterations: 3,
        on_exhaustion: 'continue',
        substep: { type: 'command', command: 'true' },
      },
      { id: 'after', type: 'command', command: 'true' },
    ];
    await stateInit({
      stateFile,
      workflow: { name: 'loop', version: '1.0', steps },
      sessionId: 'sess',
      agentId: 'agent',
    });

    await seedWorkflowDef(stateFile, steps, 'loop');
    // Loops increment per dispatch; drive through max_iterations + 1 dispatches.
    // The terminal-iteration cascade picks up the trailing command in the
    // same hook fire.
    for (let i = 0; i < 4; i++) {
      const state = await stateRead(stateFile);
      const cursor = state.cursor;
      if (cursor >= state.steps.length) break;
      const step = state.steps[cursor];
      if (step.status === 'done') break;
      await dispatchStep(steps[cursor] as any, 'post_tool_use', {}, stateFile, cursor, 0);
    }
    await maybeArchiveAfterActivation(stateFile);

    const successDir = path.join('.wheel', 'history', 'success');
    const archived = await fs.readdir(successDir).catch(() => [] as string[]);
    expect(archived.length).toBe(1);

    const archivedState = JSON.parse(
      await fs.readFile(path.join(successDir, archived[0]), 'utf-8')
    );
    expect(archivedState.steps[0].status).toBe('done'); // loop done
    expect(archivedState.steps[1].status).toBe('done'); // trailing cmd cascaded
  });
});

describe('dispatch cascade (FR-006)', () => {
  it('halts gracefully at depth cap', async () => {
    const stateFile = path.join(activeDir, '.wheel', 'state_deep.json');
    // 1002 trivial command steps. Cascade halts at depth=1000 (i.e., after
    // step 1000 has run; nextIndex=1001 < length=1002 so we don't take the
    // end_of_workflow branch first).
    const steps: any[] = [];
    for (let i = 0; i < 1002; i++) {
      steps.push({ id: `s${i}`, type: 'command', command: 'true' });
    }
    await stateInit({
      stateFile,
      workflow: { name: 'deep', version: '1.0', steps },
      sessionId: 'sess',
      agentId: 'agent',
    });
    await seedWorkflowDef(stateFile, steps, 'deep');

    await dispatchStep(steps[0] as any, 'post_tool_use', {}, stateFile, 0, 0);

    // State NOT archived — depth cap is a halt-and-resume contract.
    const exists = await fs.access(stateFile).then(() => true).catch(() => false);
    expect(exists).toBe(true);

    const state = await stateRead(stateFile);
    // Cursor advanced past the cap, but workflow not terminal.
    expect(state.cursor).toBeGreaterThan(999);
    expect(state.cursor).toBeLessThan(1002);

    // FR-006 — depth_cap halt log line emitted.
    const wheelLog = await fs.readFile(path.join('.wheel', 'wheel.log'), 'utf-8');
    expect(wheelLog).toMatch(/dispatch_cascade_halt.*reason=depth_cap/);
  }, 120_000); // 1002 execAsync('true') calls — generous timeout.
});

describe('dispatch cascade composition (FR-001 Composite, US-5)', () => {
  it('parent halts at workflow step; child cascades inside child state', async () => {
    // Write child workflow JSON to disk so workflowLoad() can resolve it.
    // workflowLoad() first parses the path as a state file and reads
    // .workflow_definition; if that fails (ValidationError), it doesn't
    // fall through to a direct read. So our fixture writes the workflow
    // wrapped in workflow_definition — same shape stateInit + handleActivation
    // produce in production.
    const childWorkflow = {
      name: 'child',
      version: '1.0',
      steps: [
        { id: 'c1', type: 'command', command: 'true' },
        { id: 'c2', type: 'command', command: 'true' },
      ],
    };
    const childPath = path.join(activeDir, 'workflows', 'child.json');
    await fs.mkdir(path.dirname(childPath), { recursive: true });
    await fs.writeFile(
      childPath,
      JSON.stringify({ ...childWorkflow, workflow_definition: childWorkflow })
    );

    const parentStateFile = path.join(activeDir, '.wheel', 'state_parent.json');
    const parentSteps = [
      { id: 'p1', type: 'command', command: 'true' },
      { id: 'p2', type: 'workflow', workflow: 'child' },
      { id: 'p3', type: 'command', command: 'true' },
    ];
    await stateInit({
      stateFile: parentStateFile,
      workflow: { name: 'parent', version: '1.0', steps: parentSteps },
      sessionId: 'sess',
      agentId: 'parent-agent',
    });
    // Persist workflow_definition for the parent so engineHandleHook can see it later.
    const parentSeed = await stateRead(parentStateFile);
    (parentSeed as any).workflow_definition = {
      name: 'parent', version: '1.0', steps: parentSteps,
    };
    await stateWrite(parentStateFile, parentSeed);

    // Activation cascade — parent step 0 runs, halts at step 1 (workflow).
    await dispatchStep(parentSteps[0] as any, 'post_tool_use', {}, parentStateFile, 0, 0);

    // Parent step 0 done; cursor at workflow step (blocking).
    const afterFirst = await stateRead(parentStateFile);
    expect(afterFirst.steps[0].status).toBe('done');
    expect(afterFirst.cursor).toBe(1);

    // Now dispatch the workflow step itself — composition activates child
    // and child cascade runs in-process inside the child state.
    await dispatchStep(parentSteps[1] as any, 'post_tool_use', {}, parentStateFile, 1, 0);

    // Child should have archived (cascade drove it terminal).
    const successDir = path.join('.wheel', 'history', 'success');
    const archived = await fs.readdir(successDir).catch(() => [] as string[]);
    const childArchive = archived.find((f) => f.startsWith('child-'));
    expect(childArchive, `expected child archive, got ${archived.join(',')}`).toBeDefined();

    const childArchivedState = JSON.parse(
      await fs.readFile(path.join(successDir, childArchive!), 'utf-8')
    );
    expect(childArchivedState.steps.every((s: any) => s.status === 'done')).toBe(true);

    // Parent cascade is paused at the workflow step (still working).
    const parentNow = await stateRead(parentStateFile);
    expect(parentNow.steps[1].status).toBe('working');
  });
});
