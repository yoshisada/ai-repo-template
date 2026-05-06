// handleDeactivate — the deactivate.sh hook handler.
//
// parity: shell post-tool-use.sh:81–176.
//
// Modes:
//   --all          → archive every state file in .wheel/state_*.json
//   <substring>    → archive state files whose basename contains arg
//   <empty>        → archive only the caller's own state file
//                    (matched by owner_session_id + owner_agent_id)
//
// After primary archive: cascade-stop child workflows (FR-018) whose
// parent_workflow points to a now-missing file, AND team agent
// sub-workflows (FR-028) whose owner_agent_id matches a teammate slot
// in any archived state.
//
// Always returns `{hookEventName: 'PostToolUse'}`.

import { promises as fs } from 'fs';
import path from 'path';
import { listLiveStateFiles } from '../../shared/state.js';
import type { HookInput, HookOutput } from '../../lib/dispatch.js';

export async function handleDeactivate(
  command: string,
  hookInput: HookInput,
): Promise<HookOutput> {
  const arg = parseDeactivateArg(command);
  const sessionId = String(hookInput.session_id ?? '');
  const agentId = String(hookInput.agent_id ?? '');

  const stoppedDir = path.join('.wheel', 'history', 'stopped');
  await fs.mkdir(stoppedDir, { recursive: true });
  const stateFiles = await listLiveStateFiles();

  if (arg === '--all') {
    for (const { path: sf } of stateFiles) await archiveOne(sf, stoppedDir);
  } else if (arg) {
    for (const { name, path: sf } of stateFiles) {
      if (name.includes(arg)) await archiveOne(sf, stoppedDir);
    }
  } else {
    for (const { path: sf } of stateFiles) {
      try {
        const s = JSON.parse(await fs.readFile(sf, 'utf-8'));
        if (s.owner_session_id === sessionId && s.owner_agent_id === agentId) {
          await archiveOne(sf, stoppedDir);
          break;
        }
      } catch { /* skip unreadable */ }
    }
  }

  await cascadeStopOrphanedChildren(stoppedDir);
  await cascadeStopTeammateSubworkflows(stoppedDir);
  return { hookEventName: 'PostToolUse' };
}

// =============================================================================
// Helpers
// =============================================================================

function parseDeactivateArg(command: string): string {
  const lines = command.split('\n').filter(l => l.includes('deactivate.sh'));
  const lastLine = lines[lines.length - 1] ?? '';
  const afterCmd = lastLine.replace(/.*deactivate\.sh\s*/, '');
  return (afterCmd.split(/\s+/)[0] ?? '').replace(/['"]/g, '');
}

async function archiveOne(sf: string, stoppedDir: string): Promise<void> {
  const ts = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*Z$/, '').replace('T', '-');
  const fname = path.basename(sf, '.json');
  const target = path.join(stoppedDir, `${fname}-${ts}.json`);
  try {
    await fs.copyFile(sf, target);
    await fs.unlink(sf);
  } catch { /* non-fatal */ }
}

/**
 * FR-018: cascade-stop child workflows whose `parent_workflow` field
 * points to a now-missing state file (their parent was just archived).
 */
async function cascadeStopOrphanedChildren(stoppedDir: string): Promise<void> {
  for (const { path: sf } of await listLiveStateFiles()) {
    try {
      const s = JSON.parse(await fs.readFile(sf, 'utf-8'));
      const parent = s.parent_workflow as string | null | undefined;
      if (parent) {
        try {
          await fs.access(parent);
        } catch {
          await archiveOne(sf, stoppedDir);
        }
      }
    } catch { /* skip */ }
  }
}

/**
 * FR-028: cascade-stop team agent sub-workflows. Walk archived state
 * files in stopped/ to find teammate agent_ids that were
 * pending/running, then archive any live state file whose
 * owner_agent_id matches.
 */
async function cascadeStopTeammateSubworkflows(stoppedDir: string): Promise<void> {
  try {
    const stoppedFiles = await fs.readdir(stoppedDir);
    const teammateAgentIds = new Set<string>();
    for (const f of stoppedFiles) {
      try {
        const s = JSON.parse(await fs.readFile(path.join(stoppedDir, f), 'utf-8')) as {
          teams?: Record<string, { teammates?: Record<string, { status?: string; agent_id?: string }> }>;
        };
        const teams = s.teams;
        if (!teams) continue;
        for (const team of Object.values(teams)) {
          const teammates = team?.teammates ?? {};
          for (const tm of Object.values(teammates)) {
            const status = tm?.status ?? '';
            const aid = tm?.agent_id ?? '';
            if ((status === 'pending' || status === 'running') && aid) {
              teammateAgentIds.add(String(aid));
            }
          }
        }
      } catch { /* skip */ }
    }
    if (teammateAgentIds.size > 0) {
      for (const { path: sf } of await listLiveStateFiles()) {
        try {
          const s = JSON.parse(await fs.readFile(sf, 'utf-8'));
          if (teammateAgentIds.has(String(s.owner_agent_id ?? ''))) {
            await archiveOne(sf, stoppedDir);
          }
        } catch { /* skip */ }
      }
    }
  } catch { /* ignore */ }
}
