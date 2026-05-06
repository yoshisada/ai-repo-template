// Pure text-extraction helpers used by the post-tool-use entry point
// to parse hook stdin and detect activate.sh / deactivate.sh invocations
// inside Bash tool_input.command.
//
// These helpers are stateless and exported so the main hook + each
// handler can share them without duplicating the regex logic.

import { promises as fs, readFileSync } from 'fs';

/**
 * Load a workflow JSON file directly. Bypasses stateRead because that
 * function rejects workflow JSON (workflow.name + steps[] don't match
 * state shape). Throws on missing required fields.
 */
export async function loadWorkflowJson(filePath: string): Promise<unknown> {
  const content = await fs.readFile(filePath, 'utf-8');
  const wf = JSON.parse(content);
  if (!wf.name) throw new Error('Invalid workflow: missing name');
  if (!Array.isArray(wf.steps) || wf.steps.length === 0) {
    throw new Error('Invalid workflow: missing steps');
  }
  for (const step of wf.steps) {
    if (!step.id) throw new Error('Invalid workflow: step missing id');
    if (!step.type) throw new Error(`Invalid workflow: step ${step.id} missing type`);
  }
  return wf;
}

/** FR-C1: Read all stdin as string synchronously (preserves newlines). */
export function readStdin(): string {
  return readFileSync('/dev/stdin', 'utf-8');
}

/**
 * FR-C1 fallback: parse hook stdin and extract `tool_input.command`.
 * Tries native JSON.parse first; falls back to python3 with strict=False
 * for inputs containing literal control chars that JSON rejects.
 */
export async function extractCommandWithFallback(rawInput: string): Promise<string> {
  try {
    const parsed = JSON.parse(rawInput);
    const cmd = parsed?.tool_input?.command as string;
    if (cmd !== undefined) return cmd;
  } catch { /* JSON.parse failed, try python3 */ }

  const { execSync } = await import('child_process');
  try {
    const cmd = execSync(
      'python3 -c "import json,sys;d=json.loads(sys.stdin.read(),strict=False);print(d.get(\'tool_input\',{}).get(\'command\',\'\'))"',
      { input: rawInput, encoding: 'utf-8', timeout: 5000 },
    );
    return cmd.trim();
  } catch {
    console.error('wheel post-tool-use: FR-C1 command extraction failed (jq + python3 both rejected hook input)');
    return '';
  }
}

/**
 * Detect `activate.sh` invocation in a multi-line Bash command. Scans
 * lines bottom-up for the first one containing `/bin/activate.sh` (cache)
 * or `plugin-wheel/bin/activate.sh` (dev). Returns the matching line or null.
 */
export function detectActivateLine(command: string): string | null {
  if (command.includes('/wheel/') && command.includes('/bin/activate.sh')) {
    const lines = command.split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].includes('/bin/activate.sh')) return lines[i];
    }
  }
  if (command.includes('plugin-wheel/bin/activate.sh')) {
    const lines = command.split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].includes('activate.sh')) return lines[i];
    }
  }
  return null;
}

/**
 * Extract workflow name from an activate.sh command line. Robust against:
 *   - quoted args (`activate.sh "tests/foo"`)
 *   - --as flag intermixed
 *   - whitespace variations
 *
 * Note: POSIX `[[:space:]]` regex doesn't work in JS — we use \s+ and
 * filter empty/quote-only tokens instead.
 */
export function extractWorkflowName(line: string): string {
  const afterActivate = line.split('activate.sh')[1]?.trim() ?? '';
  if (!afterActivate) return '';
  const tokens = afterActivate
    .split(/\s+/)
    .map(t => t.replace(/['"]/g, ''))
    .filter(t => t.length > 0 && !t.startsWith('--'));
  return tokens[0] ?? '';
}

/** Extract `--as <agent_id>` flag value from an activate.sh command line. */
export function extractAlternateAgentId(line: string): string | null {
  if (!line.includes('--as ')) return null;
  const match = line.match(/--as\s+(\S+)/);
  return match ? match[1].replace(/['"]/g, '') : null;
}
