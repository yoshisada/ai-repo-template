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