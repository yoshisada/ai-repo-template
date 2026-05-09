// FR-006: Hook event logging
import { promises as fs } from 'fs';
import path from 'path';
import { mkdirp } from '../shared/fs.js';

export interface HookEvent {
  timestamp: string;
  hookType: string;
  toolName?: string;
  sessionId?: string;
  agentId?: string;
  decision?: string;
  error?: string;
}

const LOG_DIR = '.wheel';
const LOG_FILE = 'hook-events.log';
// FR-008 (wheel-wait-all-redesign): wheel.log is the phase-tagged log used
// by archive-helper and polling-backstop sites. Distinct from hook-events.log
// (legacy fixed-schema pipe-delimited). Grep targets in SC-005 reference
// phases written here.
const WHEEL_LOG_FILE = 'wheel.log';

// FR-006: logHookEvent(event: HookEvent): Promise<void>
export async function logHookEvent(event: HookEvent): Promise<void> {
  const logPath = path.join(LOG_DIR, LOG_FILE);
  const timestamp = new Date().toISOString();
  const logLine = `${timestamp} | ${event.hookType} | ${event.toolName ?? '-'} | ${event.sessionId ?? '-'} | ${event.agentId ?? '-'} | ${event.decision ?? '-'} | ${event.error ?? ''}\n`;

  try {
    await mkdirp(LOG_DIR);
    await fs.appendFile(logPath, logLine, 'utf-8');
  } catch {
    // Logging failures should not break workflow execution
  }
}

// FR-008 (wheel-wait-all-redesign): phase-tagged log emit. Format:
//   "<iso-ts> | <phase> | k1=v1 k2=v2 ..."
// Strings are written bare; non-strings are JSON-stringified so the line
// stays grep-friendly while preserving structure for richer fields.
// Logging failures are swallowed (matches logHookEvent contract).
export async function wheelLog(
  phase: string,
  fields: Record<string, unknown>
): Promise<void> {
  const logPath = path.join(LOG_DIR, WHEEL_LOG_FILE);
  const ts = new Date().toISOString();
  const fieldStr = Object.entries(fields)
    .map(([k, v]) => {
      if (v === null || v === undefined) return `${k}=`;
      if (typeof v === 'string') return `${k}=${v}`;
      return `${k}=${JSON.stringify(v)}`;
    })
    .join(' ');
  const line = `${ts} | ${phase} | ${fieldStr}\n`;
  try {
    await mkdirp(LOG_DIR);
    await fs.appendFile(logPath, line, 'utf-8');
  } catch {
    // Logging failures should not break workflow execution
  }
}