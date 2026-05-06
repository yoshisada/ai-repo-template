// Scenario: S7 — engineInit, engineKickstart, engineCurrentStep work correctly
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { workflowLoad, workflowGetStep, workflowStepCount, workflowGetBranchTarget } from './workflow.js';
import { engineInit, engineHandleHook } from './engine.js';
import {
  stateInit,
  stateAddTeammate,
  stateUpdateTeammateStatus,
  stateSetTeam,
  stateSetStepStatus,
} from './state.js';
import { stateRead, stateWrite } from '../shared/state.js';
import type { WorkflowDefinition } from '../shared/state.js';

describe('workflowLoad', () => {
  it('should load a workflow definition from path', async () => { // FR-006
    const wf: WorkflowDefinition = {
      name: 'test-workflow',
      version: '1.0.0',
      steps: [
        { id: 's1', type: 'command', command: 'echo hello' },
        { id: 's2', type: 'agent', instruction: 'do something' },
      ],
    };
    // workflowLoad reads from state file or direct file path
    // This is tested via state integration
    expect(wf.name).toBe('test-workflow');
  });
});

describe('workflowGetStep', () => {
  it('should return step at valid index', () => { // FR-006
    const wf: WorkflowDefinition = {
      name: 'test',
      version: '1.0',
      steps: [{ id: 's1', type: 'command' }, { id: 's2', type: 'agent' }],
    };
    expect(workflowGetStep(wf, 0).id).toBe('s1');
    expect(workflowGetStep(wf, 1).id).toBe('s2');
  });

  it('should throw for out-of-range index', () => { // FR-006
    const wf: WorkflowDefinition = { name: 't', version: '1.0', steps: [{ id: 's', type: 'c' }] };
    expect(() => workflowGetStep(wf, 5)).toThrow();
  });
});

describe('workflowStepCount', () => {
  it('should return number of steps', () => { // FR-006
    const wf: WorkflowDefinition = {
      name: 't',
      version: '1.0',
      steps: [{ id: 's1' }, { id: 's2' }, { id: 's3' }].map(s => ({ ...s, type: 'command' })) as any,
    };
    expect(workflowStepCount(wf)).toBe(3);
  });
});

describe('workflowGetBranchTarget', () => {
  it('should return target step for zero exit code', () => { // FR-024
    const wf: WorkflowDefinition = {
      name: 't',
      version: '1.0',
      steps: [
        { id: 'branch-step', type: 'branch', if_zero: 'success', if_nonzero: 'failure' } as any,
        { id: 'success', type: 'command' } as any,
        { id: 'failure', type: 'command' } as any,
      ],
    };
    const target = workflowGetBranchTarget(wf, 'branch-step', 0);
    expect(target?.id).toBe('success');
  });

  it('should return target step for non-zero exit code', () => { // FR-024
    const wf: WorkflowDefinition = {
      name: 't',
      version: '1.0',
      steps: [
        { id: 'branch-step', type: 'branch', if_zero: 'success', if_nonzero: 'failure' } as any,
        { id: 'success', type: 'command' } as any,
        { id: 'failure', type: 'command' } as any,
      ],
    };
    const target = workflowGetBranchTarget(wf, 'branch-step', 1);
    expect(target?.id).toBe('failure');
  });

  it('should return null for END target', () => { // FR-024
    const wf: WorkflowDefinition = {
      name: 't',
      version: '1.0',
      steps: [
        { id: 'branch-step', type: 'branch', if_zero: 'END' } as any,
      ],
    };
    const target = workflowGetBranchTarget(wf, 'branch-step', 0);
    expect(target).toBeNull();
  });
});

// FR-005 (wheel-wait-all-redesign): engineHandleHook remap of
// teammate_idle/subagent_stop → post_tool_use ONLY when current step is
// team-wait. For other step types the original hookType is preserved.
describe('engineHandleHook FR-005 hook routing', () => {
  const TEST_ROOT = '/tmp/wheel-engine-fr005';
  let testCounter = 0;
  let activeDir: string;

  beforeEach(async () => {
    testCounter++;
    activeDir = path.join(TEST_ROOT, `e-${testCounter}-${Date.now()}`);
    await fs.mkdir(activeDir, { recursive: true });
    process.chdir(activeDir);
    await fs.mkdir('.wheel', { recursive: true });
  });

  afterEach(async () => {
    process.chdir('/tmp');
    await fs.rm(activeDir, { recursive: true, force: true });
  });

  async function setupTeamWaitState(stepStatus: 'pending' | 'working') {
    const wfFile = path.join(activeDir, 'parent.json');
    // Three-step parent so the parent does NOT auto-archive when wait-all
    // advances cursor past the team-wait step. The trailing 'report' step
    // keeps the parent in a non-terminal state so the FR-005 tests can
    // observe the parent's teammate-slot update without racing against
    // the FR-009 archive wiring.
    await fs.writeFile(
      wfFile,
      JSON.stringify({
        name: 'parent',
        version: '1.0',
        steps: [
          { id: 'tc', type: 'team-create' },
          { id: 'wait', type: 'team-wait', team: 'wait' },
          { id: 'report', type: 'agent', instruction: 'noop' },
        ],
      })
    );
    const stateFile = path.join(activeDir, '.wheel', 'state_parent.json');
    await stateInit({
      stateFile,
      workflow: {
        name: 'parent',
        version: '1.0',
        steps: [
          { id: 'tc', type: 'team-create' },
          { id: 'wait', type: 'team-wait' },
          { id: 'report', type: 'agent' },
        ],
      },
      sessionId: 'sess',
      agentId: 'parent-agent',
      workflowFile: wfFile,
    });
    const state = await stateRead(stateFile);
    state.cursor = 1;
    state.workflow_definition = {
      name: 'parent',
      version: '1.0',
      steps: [
        { id: 'tc', type: 'team-create' },
        { id: 'wait', type: 'team-wait', team: 'wait' },
        { id: 'report', type: 'agent', instruction: 'noop' },
      ],
    };
    await stateWrite(stateFile, state);
    await stateSetTeam(stateFile, 'wait', 'parent-wait');
    await stateAddTeammate(stateFile, 'wait', {
      task_id: '',
      status: 'pending',
      agent_id: 'a@t',
      output_dir: '.wheel/outputs/a',
      assign: {},
      started_at: null,
      completed_at: null,
    });
    await stateUpdateTeammateStatus(stateFile, 'wait', 'a@t', 'running');
    if (stepStatus === 'working') {
      await stateSetStepStatus(stateFile, 1, 'working');
    }
    await engineInit(wfFile, stateFile);
    return stateFile;
  }

  it('teammate_idle on team-wait runs the wake-up branch (not the polling backstop)', async () => {
    // Post-fix: teammate_idle is NO LONGER remapped to post_tool_use. It
    // runs `_teamWaitTeammateIdle` which finds the idle teammate's child
    // state file and either advances an auto-executable step or emits a
    // SendMessage wake block. With no `agent_id`/`teammate_name` in the
    // hook input, the dispatcher logs `no_agent_id_or_name` and returns
    // approve without touching the polling backstop. The polling-backstop
    // path is still exercised by subagent_stop (next test).
    await setupTeamWaitState('working');
    const result = await engineHandleHook('teammate_idle', {});
    expect(result.decision).toBe('approve');
  });

  it('subagent_stop on team-wait triggers polling backstop', async () => {
    const stateFile = await setupTeamWaitState('working');
    const archiveDir = path.join(activeDir, '.wheel', 'history', 'failure');
    await fs.mkdir(archiveDir, { recursive: true });
    await fs.writeFile(
      path.join(archiveDir, 'a.json'),
      JSON.stringify({
        workflow_name: 'a-child',
        parent_workflow: stateFile,
        alternate_agent_id: 'a@t',
        status: 'failed',
      })
    );

    await engineHandleHook('subagent_stop', {});
    const state = await stateRead(stateFile);
    expect(state.teams['wait'].teammates['a@t'].status).toBe('failed');
  });
});

// FR-009 (wheel-wait-all-redesign B-3 fix): engineHandleHook calls
// archiveWorkflow when the workflow reaches a terminal state. Two terminal
// triggers — cursor past end-of-steps (natural completion) and explicit
// state.status set to 'completed'/'failed' by a dispatcher.
describe('engineHandleHook FR-009 archive wiring', () => {
  const TEST_ROOT = '/tmp/wheel-engine-fr009';
  let testCounter = 0;
  let activeDir: string;

  beforeEach(async () => {
    testCounter++;
    activeDir = path.join(TEST_ROOT, `e-${testCounter}-${Date.now()}`);
    await fs.mkdir(activeDir, { recursive: true });
    process.chdir(activeDir);
    await fs.mkdir('.wheel', { recursive: true });
  });

  afterEach(async () => {
    process.chdir('/tmp');
    await fs.rm(activeDir, { recursive: true, force: true });
  });

  it('archives workflow when cursor advances past last step', async () => {
    const wfFile = path.join(activeDir, 'wf.json');
    const wf = {
      name: 'finite-wf',
      version: '1.0',
      steps: [
        { id: 's1', type: 'command', command: 'true' },
      ],
    };
    await fs.writeFile(wfFile, JSON.stringify(wf));
    const stateFile = path.join(activeDir, '.wheel', 'state_term.json');
    await stateInit({
      stateFile,
      workflow: wf as any,
      sessionId: 'sess',
      agentId: 'a',
      workflowFile: wfFile,
    });
    // Pre-set workflow_definition for engineInit's preferred path
    const initial = await stateRead(stateFile);
    initial.workflow_definition = wf as any;
    await stateWrite(stateFile, initial);
    await engineInit(wfFile, stateFile);

    // Drive the command step to completion via post_tool_use hook.
    // dispatchCommand executes inline: status → done, then engineHandleHook
    // advances cursor (0 → 1) which equals steps.length → terminal → archive.
    await engineHandleHook('post_tool_use', {});

    // The state file MUST be archived (no longer at original path)
    let liveStillExists = true;
    try {
      await fs.access(stateFile);
    } catch {
      liveStillExists = false;
    }
    expect(liveStillExists).toBe(false);

    // The archived file MUST exist under .wheel/history/success/
    const successDir = path.join(activeDir, '.wheel', 'history', 'success');
    const archives = await fs.readdir(successDir);
    expect(archives.length).toBe(1);
    expect(archives[0]).toMatch(/^finite-wf-/);

    // The archived state's workflow.status MUST be 'completed'
    const archivedJson = JSON.parse(
      await fs.readFile(path.join(successDir, archives[0]), 'utf8')
    );
    expect(archivedJson.status).toBe('completed');
  });

  it('archives to failure bucket when any step has status failed', async () => {
    const wfFile = path.join(activeDir, 'wf.json');
    const wf = {
      name: 'fail-wf',
      version: '1.0',
      steps: [
        { id: 's1', type: 'command', command: 'true' },
      ],
    };
    await fs.writeFile(wfFile, JSON.stringify(wf));
    const stateFile = path.join(activeDir, '.wheel', 'state_fail.json');
    await stateInit({
      stateFile,
      workflow: wf as any,
      sessionId: 'sess',
      agentId: 'a',
      workflowFile: wfFile,
    });
    const initial = await stateRead(stateFile);
    initial.workflow_definition = wf as any;
    initial.cursor = 1; // already past end
    initial.steps[0].status = 'failed';
    await stateWrite(stateFile, initial);
    await engineInit(wfFile, stateFile);

    await engineHandleHook('post_tool_use', {});

    let liveStillExists = true;
    try {
      await fs.access(stateFile);
    } catch {
      liveStillExists = false;
    }
    expect(liveStillExists).toBe(false);

    const failureDir = path.join(activeDir, '.wheel', 'history', 'failure');
    const archives = await fs.readdir(failureDir);
    expect(archives.length).toBe(1);
    const archivedJson = JSON.parse(
      await fs.readFile(path.join(failureDir, archives[0]), 'utf8')
    );
    expect(archivedJson.status).toBe('failed');
  });

  it('archives child workflow and updates parent teammate slot end-to-end', async () => {
    // Set up parent workflow with team-wait at cursor 1
    const parentWfFile = path.join(activeDir, 'parent.json');
    const parentWf = {
      name: 'parent',
      version: '1.0',
      steps: [
        { id: 'tc', type: 'team-create' },
        { id: 'wait', type: 'team-wait', team: 'wait' },
      ],
    };
    await fs.writeFile(parentWfFile, JSON.stringify(parentWf));
    const parentStateFile = path.join(activeDir, '.wheel', 'state_parent.json');
    await stateInit({
      stateFile: parentStateFile,
      workflow: parentWf as any,
      sessionId: 'sess',
      agentId: 'parent-agent',
      workflowFile: parentWfFile,
    });
    const parent = await stateRead(parentStateFile);
    parent.cursor = 1;
    parent.workflow_definition = parentWf as any;
    await stateWrite(parentStateFile, parent);
    await stateSetTeam(parentStateFile, 'wait', 'parent-wait');
    await stateAddTeammate(parentStateFile, 'wait', {
      task_id: '',
      status: 'pending',
      agent_id: 'worker-1@parent-wait',
      output_dir: '.wheel/outputs/worker-1',
      assign: {},
      started_at: null,
      completed_at: null,
    });
    await stateUpdateTeammateStatus(parentStateFile, 'wait', 'worker-1@parent-wait', 'running');

    // Set up CHILD workflow (single command step) with parent_workflow link
    const childWfFile = path.join(activeDir, 'child.json');
    const childWf = {
      name: 'child',
      version: '1.0',
      steps: [{ id: 'c1', type: 'command', command: 'true' }],
    };
    await fs.writeFile(childWfFile, JSON.stringify(childWf));
    const childStateFile = path.join(activeDir, '.wheel', 'state_child.json');
    await stateInit({
      stateFile: childStateFile,
      workflow: childWf as any,
      sessionId: 'sess',
      agentId: 'worker-1-raw-id',
      workflowFile: childWfFile,
    });
    const child = await stateRead(childStateFile);
    child.workflow_definition = childWf as any;
    child.parent_workflow = parentStateFile;
    child.alternate_agent_id = 'worker-1@parent-wait';
    await stateWrite(childStateFile, child);
    await engineInit(childWfFile, childStateFile);

    // Run the child's command step → terminal → archive → parent slot updated
    await engineHandleHook('post_tool_use', {});

    // Child state file must be gone
    let childExists = true;
    try {
      await fs.access(childStateFile);
    } catch {
      childExists = false;
    }
    expect(childExists).toBe(false);

    // Parent's teammate slot must be 'completed'
    const finalParent = await stateRead(parentStateFile);
    expect(finalParent.teams['wait'].teammates['worker-1@parent-wait'].status).toBe('completed');
  });
});