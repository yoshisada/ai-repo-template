// Archive + parent-state helpers (wheel-wait-all-redesign).
//
// LOCK ORDERING (FR-007): nothing here takes a child state-file lock.
// archiveWorkflow reads the child state OUTSIDE any lock (the child
// workflow is terminal — no concurrent writers) and then takes the
// PARENT lock via stateUpdateParentTeammateSlot /
// maybeAdvanceParentTeamWaitCursor. Two siblings archiving
// simultaneously contend on the parent lock and serialize via
// withLockBlocking's jittered backoff; each updates a disjoint slot,
// so both writes land.
//
// FR-001 / FR-002 / FR-006 / FR-009.

import { promises as fs } from 'fs';
import os from 'os';
import path from 'path';
import { stateRead, stateWrite } from '../shared/state.js';
import type { WheelState, TeammateEntry } from '../shared/state.js';
import { mkdirp } from '../shared/fs.js';
import { withLockBlocking } from './lock.js';
import { wheelLog } from './log.js';
import { stateSetCursor, stateSetStepStatus } from './state.js';

/**
 * FR-001: mutate `parent.teams[<team_id>].teammates[<name>]` where
 * `slot.agent_id === childAlternateAgentId`. Returns `null` if no slot
 * matches. Acquires parent lock (FR-007: caller MUST NOT hold any other
 * state-file lock).
 */
export async function stateUpdateParentTeammateSlot(
  parentStateFile: string,
  childAlternateAgentId: string,
  newStatus: 'completed' | 'failed',
): Promise<{ teamId: string; teammateName: string } | null> {
  return withLockBlocking(parentStateFile, async () => {
    let parent: WheelState;
    try {
      parent = await stateRead(parentStateFile);
    } catch {
      // FR-001 EC-1: parent missing/corrupt. Caller logs the warning.
      return null;
    }

    let foundTeam: string | null = null;
    let foundName: string | null = null;
    for (const [teamId, team] of Object.entries(parent.teams ?? {})) {
      const teammates = (team as { teammates?: Record<string, TeammateEntry> }).teammates ?? {};
      for (const [name, slot] of Object.entries(teammates)) {
        if (slot && slot.agent_id === childAlternateAgentId) {
          foundTeam = teamId;
          foundName = name;
          break;
        }
      }
      if (foundTeam) break;
    }
    if (!foundTeam || !foundName) return null;

    const now = new Date().toISOString();
    const slot = parent.teams[foundTeam].teammates[foundName];
    slot.status = newStatus;
    slot.completed_at = now;
    parent.updated_at = now;
    await stateWrite(parentStateFile, parent);
    return { teamId: foundTeam, teammateName: foundName };
  });
}

/**
 * FR-002: if parent's current step is `team-wait` AND its `team` field
 * matches `teamId` AND every teammate has terminal status, mark the
 * step done and advance cursor (skipping conditionally skipped steps).
 * Otherwise no-op. Acquires parent lock.
 */
export async function maybeAdvanceParentTeamWaitCursor(
  parentStateFile: string,
  teamId: string,
): Promise<boolean> {
  return withLockBlocking(parentStateFile, async () => {
    let parent: WheelState;
    try {
      parent = await stateRead(parentStateFile);
    } catch { return false; }

    const cursor = parent.cursor ?? 0;
    const step = parent.steps?.[cursor];
    if (!step || step.type !== 'team-wait') return false;

    // Resolve the team field from workflow_definition (hot path); fall
    // back to step.id to match dispatchTeamWait's `step.team ?? step.id`.
    const wfDef = parent.workflow_definition;
    const wfStep = wfDef?.steps?.[cursor] as { team?: string; id?: string } | undefined;
    const stepTeam = wfStep?.team ?? wfStep?.id ?? step.id;
    if (stepTeam !== teamId) return false;

    const team = parent.teams?.[teamId];
    if (!team) return false;
    const teammates = team.teammates ?? {};
    for (const name of Object.keys(teammates)) {
      const status = teammates[name]?.status ?? 'pending';
      if (status !== 'completed' && status !== 'failed') return false;
    }

    const now = new Date().toISOString();
    step.status = 'done';
    step.completed_at = now;
    // advance_past_skipped: bump cursor past contiguous 'skipped' steps.
    let next = cursor + 1;
    while (
      next < parent.steps.length
      && parent.steps[next]
      && parent.steps[next].status === 'skipped'
    ) {
      next++;
    }
    parent.cursor = next;
    parent.updated_at = now;
    await stateWrite(parentStateFile, parent);
    return true;
  });
}

/**
 * Always-run cleanup contract: when a workflow archives (success,
 * failure, or stopped), every team registered via this workflow's
 * `team-create` steps gets its `~/.claude/teams/<name>/` directory
 * removed. Mirrors what TeamDelete would do on the happy path, but
 * fires regardless of how we got to terminal — including:
 *
 *   - mid-workflow step failure (engine archives to history/failure/)
 *   - user-invoked /wheel:wheel-stop (handle-deactivate archives to
 *     history/stopped/)
 *   - polling-backstop reconciliation that flips a teammate slot to
 *     failed (engine then archives the parent normally)
 *
 * Without this contract, a workflow that crashes mid-flight leaves
 * its team configs behind in `~/.claude/teams/`, and the next run of
 * the same workflow fails immediately on TeamCreate with
 * `Team "<name>" already exists`. That's the failure mode that hit
 * bifrost-minimax-team-{single-haiku, mixed-model} on 2026-05-08.
 *
 * Best-effort: each team cleanup is wrapped in its own try/catch so
 * a single rm failure can't block other team cleanups or the archive
 * itself. Errors are logged via wheelLog.
 *
 * Idempotent: if the team dir is already gone (happy path completed
 * normally), `fs.rm({ force: true })` is a no-op.
 */
export async function runArchiveFinalizers(child: WheelState): Promise<void> {
  const wfDef = child.workflow_definition;
  if (!wfDef?.steps) return;

  // Collect team names referenced by this workflow's team-create
  // steps. Workflow JSON shape: { type: "team-create", team_name: "..." }.
  const teamNames = new Set<string>();
  for (const step of wfDef.steps) {
    const stepObj = step as { type?: string; team_name?: string; finalizer?: boolean };
    if (stepObj.type === 'team-create' && typeof stepObj.team_name === 'string') {
      teamNames.add(stepObj.team_name);
    }
    // Future extension: respect a generic `"finalizer": true` flag on
    // arbitrary steps so workflows can declare custom cleanup. For
    // v1, only team-create has well-defined wheel-side cleanup
    // semantics (rm -rf ~/.claude/teams/<name>/), so we restrict to
    // that path. Generic finalizers requiring orchestrator-mediated
    // tool calls (e.g. SendMessage to a still-running teammate) need
    // a separate design and are out of scope for this fix.
  }
  if (teamNames.size === 0) return;

  const teamsRoot = path.join(os.homedir(), '.claude', 'teams');
  for (const teamName of teamNames) {
    // Defensive validation: team_name should never contain path
    // separators, but check anyway so a malformed workflow can't
    // escape the teams root via "../etc/passwd"-shaped names.
    if (teamName.includes('/') || teamName.includes('\\') || teamName === '..' || teamName === '.') {
      await wheelLog('archive_finalizer_skipped_invalid_name', {
        team_name: teamName,
      });
      continue;
    }
    const teamDir = path.join(teamsRoot, teamName);
    try {
      await fs.rm(teamDir, { recursive: true, force: true });
      await wheelLog('archive_finalizer_team_cleanup', {
        team_name: teamName,
        team_dir: teamDir,
      });
    } catch (err) {
      await wheelLog('archive_finalizer_team_cleanup_error', {
        team_name: teamName,
        team_dir: teamDir,
        error: String(err instanceof Error ? err.message : err),
      });
    }
  }
}

/**
 * Single deterministic call path for archiving a workflow's state file
 * to `.wheel/history/<bucket>/`. Updates the parent slot first (when
 * applicable), then renames the child state file.
 */
export async function archiveWorkflow(
  stateFile: string,
  bucket: 'success' | 'failure' | 'stopped',
): Promise<string> {
  const child = await stateRead(stateFile);
  const parentPath = child.parent_workflow ?? null;
  const childAlternate = child.alternate_agent_id ?? null;

  let updateResult: { teamId: string; teammateName: string } | null = null;
  let cursorAdvanced = false;

  if (parentPath && childAlternate) {
    updateResult = await maybeUpdateParentSlot(parentPath, childAlternate, bucket);
    if (updateResult) {
      cursorAdvanced = await maybeAdvanceParentTeamWaitCursor(parentPath, updateResult.teamId);
    }
    await logArchiveParentUpdate(parentPath, childAlternate, updateResult, cursorAdvanced, bucket);
  }

  if (parentPath && !updateResult) {
    await maybeAdvanceParentCompositionStep(parentPath);
  }

  // Preemptive parent-sentinel write after a parent cursor advance.
  //
  // Why: when archiveWorkflow advances the parent past its team-wait
  // step, the parent's NEW cursor step (typically team-delete cleanup)
  // never gets dispatched-and-emitted in this hook fire because we're
  // running inside the SUB-AGENT'S session's hook handler. The parent's
  // own session won't dispatch the new step until its NEXT Stop hook
  // fires, but in `claude --print` mode the parent's polling-Read on a
  // file with unchanged mtime returns "Wasted call — file unchanged"
  // and the orchestrator decides nothing changed and ends the run
  // without ever triggering a fresh hook.
  //
  // Write the parent's new cursor step's instruction to
  // `.wheel/.next-instruction.md` directly here, mirroring
  // handle-activate.ts's preemptive-write pattern. The orchestrator's
  // next sentinel read sees the new instruction's mtime change → fresh
  // content → executes team-delete → workflow archives cleanly.
  if (parentPath && cursorAdvanced) {
    try {
      const parent = await stateRead(parentPath);
      const cursor = parent.cursor ?? 0;
      const wfDef = parent.workflow_definition;
      const step = wfDef?.steps?.[cursor] ?? parent.steps?.[cursor];
      const totalSteps = wfDef?.steps?.length ?? parent.steps.length;
      if (step && cursor < totalSteps) {
        // dispatchStep is in lib/dispatch.ts — dynamic import to avoid
        // a static cycle with archive (state-archive ← dispatch ← engine
        // ← state-archive).
        const dispatchModule = await import('./dispatch.js');
        const out = await dispatchModule.dispatchStep(
          step as import('../shared/state.js').WorkflowStep,
          'stop',
          { session_id: parent.owner_session_id ?? '' } as import('./dispatch-types.js').HookInput,
          parentPath,
          cursor,
          0,
        );
        if (out.decision === 'block' && typeof out.additionalContext === 'string' && out.additionalContext.length > 0) {
          const stateDir = path.dirname(parentPath);
          const sentinelPath = path.join(stateDir, '.next-instruction.md');
          // Only write if content differs (mirrors emit.ts byte-identity skip).
          let priorBody = '';
          try { priorBody = await fs.readFile(sentinelPath, 'utf-8'); } catch { /* missing */ }
          const priorWithoutStamp = priorBody.replace(/^<!-- wheel hook instruction — [^>]+ -->\n\n/, '');
          const newWithoutStamp = `${out.additionalContext}\n`;
          if (priorWithoutStamp !== newWithoutStamp) {
            const stamp = new Date().toISOString();
            const body = `<!-- wheel hook instruction — ${stamp} -->\n\n${out.additionalContext}\n`;
            await fs.writeFile(sentinelPath, body, 'utf-8');
          }
        }
      }
    } catch { /* non-fatal: dispatch failure during preemptive write */ }
  }

  // Run always-on finalizers (team-config cleanup, etc.) BEFORE the
  // rename. Doing this before the archive means: (a) the state file
  // is still readable for the finalizer's workflow_definition lookup
  // — actually we already have `child` in scope, so the lookup
  // doesn't depend on the file; (b) if a finalizer fails AND the
  // archive fails, we don't end up with a finalized-but-not-archived
  // workflow that re-runs finalizers on a retry. Idempotency makes
  // ordering safe either way; we pick "before" for clarity.
  await runArchiveFinalizers(child);

  // FR-009: rename child to history bucket.
  const archivedPath = await renameToHistory(stateFile, child, bucket);

  // Sentinel cleanup: if no live state files remain after this archive,
  // delete `.wheel/.next-instruction.md` so the orchestrator's next
  // poll-read sees "file not found" (the unambiguous termination signal
  // per the harness fixture's Hard Rule: "stop polling when sentinel is
  // missing OR has same timestamp"). Less-reliable orchestrators that
  // can't reason about same-timestamp equality (MiniMax-M2.7 et al.)
  // need the missing-file path to terminate cleanly.
  //
  // Why guarded by "no other live state files": multiple workflows can
  // share a single `.wheel/` directory (e.g. a sub-workflow archiving
  // while the parent is still alive). Deleting the sentinel while a
  // parent still expects to read it would break parent progression.
  // Only when ZERO state_*.json remain is the sentinel guaranteed
  // unused.
  try {
    const stateDir = path.dirname(stateFile);
    const entries = await fs.readdir(stateDir).catch(() => [] as string[]);
    const liveStateFiles = entries.filter((e) => e.startsWith('state_') && e.endsWith('.json'));
    if (liveStateFiles.length === 0) {
      await fs.unlink(path.join(stateDir, '.next-instruction.md')).catch(() => undefined);
    }
  } catch { /* non-fatal */ }

  return archivedPath;
}

// =============================================================================
// archiveWorkflow internals
// =============================================================================

async function maybeUpdateParentSlot(
  parentPath: string,
  childAlternate: string,
  bucket: 'success' | 'failure' | 'stopped',
): Promise<{ teamId: string; teammateName: string } | null> {
  // FR-001 EC-1: parent state file missing → log and skip.
  try {
    await fs.access(parentPath);
  } catch {
    await wheelLog('archive_parent_update_skipped', {
      child_agent_id: childAlternate,
      parent_state_file: parentPath,
      reason: 'parent_state_file_missing',
    });
    return null;
  }
  const newStatus: 'completed' | 'failed' = bucket === 'success' ? 'completed' : 'failed';
  try {
    return await stateUpdateParentTeammateSlot(parentPath, childAlternate, newStatus);
  } catch (err) {
    await wheelLog('archive_parent_update_error', {
      child_agent_id: childAlternate,
      parent_state_file: parentPath,
      error: String(err instanceof Error ? err.message : err),
    });
    return null;
  }
}

async function logArchiveParentUpdate(
  parentPath: string,
  childAlternate: string,
  updateResult: { teamId: string; teammateName: string } | null,
  cursorAdvanced: boolean,
  bucket: 'success' | 'failure' | 'stopped',
): Promise<void> {
  if (!updateResult) {
    await wheelLog('archive_parent_update_no_match', {
      child_agent_id: childAlternate,
      parent_state_file: parentPath,
    });
    return;
  }
  const newStatus = bucket === 'success' ? 'completed' : 'failed';
  await wheelLog('archive_parent_update', {
    child_agent_id: childAlternate,
    parent_state_file: parentPath,
    team_id: updateResult.teamId,
    teammate_name: updateResult.teammateName,
    new_status: newStatus,
    cursor_advanced: cursorAdvanced,
  });
}

/**
 * Composition parent-resume (parity: shell dispatch.sh:144). When child
 * has a parent_workflow but no alternate_agent_id (or no teammate slot
 * matched), this is a workflow-step composition parent. Find the
 * parent's currently-working `workflow` step, mark it done, advance
 * cursor past skipped steps.
 */
async function maybeAdvanceParentCompositionStep(parentPath: string): Promise<void> {
  try {
    await fs.access(parentPath);
    const parent = await stateRead(parentPath);
    const workingIdx = parent.steps.findIndex(
      (s) => s.type === 'workflow' && s.status === 'working',
    );
    if (workingIdx < 0) return;
    await stateSetStepStatus(parentPath, workingIdx, 'done');
    const wfDef = parent.workflow_definition;
    let nextIdx = workingIdx + 1;
    if (wfDef?.steps) {
      const stepJson = wfDef.steps[workingIdx];
      const wfMod = await import('./workflow.js');
      const rawNext = wfMod.resolveNextIndex(stepJson, workingIdx, wfDef);
      nextIdx = await wfMod.advancePastSkipped(parentPath, rawNext, wfDef);
    }
    await stateSetCursor(parentPath, nextIdx);
    await wheelLog('archive_parent_compose_advance', {
      parent_state_file: parentPath,
      parent_step_index: workingIdx,
      new_cursor: nextIdx,
    });
  } catch { /* parent missing/unreadable — already logged above */ }
}

async function renameToHistory(
  stateFile: string,
  child: WheelState,
  bucket: 'success' | 'failure' | 'stopped',
): Promise<string> {
  const archiveDir = path.join('.wheel', 'history', bucket);
  await mkdirp(archiveDir);
  const workflowName = child.workflow_name || 'workflow';
  const ts = new Date().toISOString()
    .replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z').replace('T', '-');
  const compactTs = ts.replace(/Z$/, '');
  const stateBasename = path.basename(stateFile, '.json');
  const stateId = stateBasename.replace(/^state_/, '');
  const target = path.join(archiveDir, `${workflowName}-${compactTs}-${stateId}.json`);

  try {
    await fs.rename(stateFile, target);
  } catch (err) {
    // EXDEV (cross-device) → fall back to copy + unlink.
    if ((err as NodeJS.ErrnoException).code === 'EXDEV') {
      await fs.copyFile(stateFile, target);
      await fs.unlink(stateFile);
    } else {
      throw err;
    }
  }
  return target;
}
