// FR-002 — dispatchAgent 6 sub-fixes parity tests.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { dispatchStep } from './dispatch.js';
import { stateInit } from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';

const TEST_DIR = '/tmp/wheel-dispatch-agent-parity';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

// Helper to build a state file backed by a workflow_definition.
async function setupAgentStep(opts: {
  stateFile: string;
  step: any;
  awaitingUserInput?: boolean;
}) {
  await stateInit({
    stateFile: opts.stateFile,
    workflow: { name: 'wf', version: '1.0', steps: [opts.step] },
    sessionId: 's1',
    agentId: '',
  });
  // wire workflow_definition for resolveNextIndex
  const s = await stateRead(opts.stateFile);
  (s as any).workflow_definition = { name: 'wf', version: '1.0', steps: [opts.step] };
  if (opts.awaitingUserInput) {
    s.steps[0].awaiting_user_input = true;
    s.steps[0].awaiting_user_input_reason = 'test';
    s.steps[0].awaiting_user_input_since = new Date().toISOString();
  }
  await stateWrite(opts.stateFile, s);
}

describe('dispatchAgent FR-002 parity', () => {
  // FR-002 A1
  it('deletes stale output file on pending→working transition', async () => {
    const statePath = path.join(TEST_DIR, 'stale-out.json');
    const outFile = path.join(TEST_DIR, 'agent-output.txt');
    await fs.writeFile(outFile, 'STALE');

    const step = { id: 's1', type: 'agent', instruction: 'do', output: outFile };
    await setupAgentStep({ stateFile: statePath, step });

    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    // Stale file should be gone
    await expect(fs.access(outFile)).rejects.toThrow();
  });

  // FR-002 A2
  it('cursor advance respects skipped + next field via resolveNextIndex', async () => {
    const statePath = path.join(TEST_DIR, 'cursor-resolve.json');
    const outFile = path.join(TEST_DIR, 'a-out.txt');

    const stepA = { id: 'a', type: 'agent', instruction: 'a', output: outFile, next: 'c' };
    const stepB = { id: 'b', type: 'agent', instruction: 'b' };
    const stepC = { id: 'c', type: 'agent', instruction: 'c' };

    await stateInit({
      stateFile: statePath,
      workflow: { name: 'wf', version: '1.0', steps: [stepA, stepB, stepC] },
      sessionId: 's1',
      agentId: '',
    });
    const s = await stateRead(statePath);
    (s as any).workflow_definition = { name: 'wf', version: '1.0', steps: [stepA, stepB, stepC] };
    s.steps[0].status = 'working';
    await stateWrite(statePath, s);

    // simulate agent completing — write output file
    await fs.writeFile(outFile, 'done');

    await dispatchStep(stepA as any, 'stop', {}, statePath, 0);

    const finalState = await stateRead(statePath);
    // cursor should advance to 'c' (index 2), not 'b' (index 1)
    expect(finalState.cursor).toBe(2);
  });

  // FR-002 A3
  it('clears awaiting_user_input on advance', async () => {
    const statePath = path.join(TEST_DIR, 'aui.json');
    const outFile = path.join(TEST_DIR, 'aui-out.txt');
    const step = { id: 's1', type: 'agent', instruction: 'do', output: outFile };

    await setupAgentStep({ stateFile: statePath, step, awaitingUserInput: true });
    // mark working
    {
      const s = await stateRead(statePath);
      s.steps[0].status = 'working';
      await stateWrite(statePath, s);
    }
    await fs.writeFile(outFile, 'done');

    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    const finalState = await stateRead(statePath);
    expect(finalState.steps[0].awaiting_user_input).toBe(false);
  });

  // FR-002 A4
  it('contextCaptureOutput stores output instead of nulling on advance', async () => {
    const statePath = path.join(TEST_DIR, 'capture.json');
    const outFile = path.join(TEST_DIR, 'cap-out.txt');
    const step = { id: 's1', type: 'agent', instruction: 'do', output: outFile };

    await setupAgentStep({ stateFile: statePath, step });
    {
      const s = await stateRead(statePath);
      s.steps[0].status = 'working';
      await stateWrite(statePath, s);
    }
    await fs.writeFile(outFile, 'agent-result');

    await dispatchStep(step as any, 'stop', {}, statePath, 0);

    const finalState = await stateRead(statePath);
    // FR-002 A4: output is captured (not nulled out)
    expect(finalState.steps[0].output).toBe(outFile);
  });

  // FR-002 A5
  it('advances parent cursor after terminal child archive', async () => {
    // Set up a "parent" state file pointing to a workflow with a single step.
    const parentPath = path.join(TEST_DIR, 'parent.json');
    const parentWfFile = path.join(TEST_DIR, 'parent-wf.json');
    const parentStep = { id: 'p1', type: 'agent', instruction: 'parent step' };
    const parentWf = { name: 'parent-wf', version: '1.0', steps: [parentStep] };
    await fs.writeFile(parentWfFile, JSON.stringify(parentWf));
    await stateInit({
      stateFile: parentPath,
      workflow: parentWf,
      sessionId: 's1',
      agentId: '',
    });
    {
      const s = await stateRead(parentPath);
      s.workflow_file = parentWfFile;
      (s as any).workflow_definition = parentWf;
      await stateWrite(parentPath, s);
    }

    // Set up child state with parent_workflow set to parent path.
    const childPath = path.join(TEST_DIR, 'child.json');
    const outFile = path.join(TEST_DIR, 'child-out.txt');
    const childStep = { id: 'c1', type: 'agent', instruction: 'child', output: outFile, terminal: true };
    await stateInit({
      stateFile: childPath,
      workflow: { name: 'child-wf', version: '1.0', steps: [childStep] },
      sessionId: 's1',
      agentId: '',
    });
    {
      const s = await stateRead(childPath);
      (s as any).parent_workflow = parentPath;
      (s as any).workflow_definition = { name: 'child-wf', version: '1.0', steps: [childStep] };
      s.steps[0].status = 'working';
      await stateWrite(childPath, s);
    }
    await fs.writeFile(outFile, 'child-done');

    // Driving the child to done should fire _chainParentAfterArchive and
    // dispatch the parent's first step. We assert that the resolved-step
    // emits a `block` with additionalContext (i.e. dispatchStep was called
    // on the parent with stop semantics).
    const result = await dispatchStep(childStep as any, 'stop', {}, childPath, 0);

    // child returns approve after advancing
    expect(result.decision).toBe('approve');
    // child's status is 'done'
    const finalChild = await stateRead(childPath);
    expect(finalChild.steps[0].status).toBe('done');
    // parent step transitioned pending→working via _chainParentAfterArchive
    const finalParent = await stateRead(parentPath);
    expect(finalParent.steps[0].status).toBe('working');
  });

  // FR-002 A6
  it('emits no DEBUG console output during stop hook', async () => {
    const statePath = path.join(TEST_DIR, 'no-debug.json');
    const outFile = path.join(TEST_DIR, 'nd-out.txt');
    const step = { id: 's1', type: 'agent', instruction: 'do', output: outFile };

    await setupAgentStep({ stateFile: statePath, step });

    const original = console.error;
    const errs: string[] = [];
    console.error = ((...args: unknown[]) => { errs.push(args.map(String).join(' ')); }) as any;
    try {
      await dispatchStep(step as any, 'stop', {}, statePath, 0);
      // mark working + write output, dispatch again
      {
        const s = await stateRead(statePath);
        s.steps[0].status = 'working';
        await stateWrite(statePath, s);
      }
      await fs.writeFile(outFile, 'done');
      await dispatchStep(step as any, 'stop', {}, statePath, 0);
    } finally {
      console.error = original;
    }

    const debugOutput = errs.filter(e => e.includes('DEBUG'));
    expect(debugOutput).toEqual([]);
  });
});
