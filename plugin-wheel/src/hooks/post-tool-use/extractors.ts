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
 * Escape literal U+0000..U+001F bytes that appear inside JSON string
 * contexts in `raw`. Returns a string that's compliant JSON.
 *
 * Why this exists: Claude Code's hook harness emits `tool_input.command`
 * with raw newlines / tabs / etc. inside the string value. The JSON spec
 * requires those bytes to be escaped (\\n, \\t, \\u0000…). Native
 * `JSON.parse` rejects raw control chars, so we pre-process the bytes:
 * walk a tiny state machine that tracks whether we're currently inside
 * a string value, and rewrite any unescaped control char to its JSON
 * escape sequence. Outside strings, control bytes are passed through
 * unchanged (legal as inter-token whitespace).
 *
 * This replaces the previous python3 strict=False fallback — wheel now
 * has zero runtime python dependency.
 */
function escapeJsonStringControlChars(raw: string): string {
  let inString = false;
  let escape = false;
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    const code = raw.charCodeAt(i);
    if (escape) {
      out += c;
      escape = false;
      continue;
    }
    if (c === '\\') {
      out += c;
      escape = true;
      continue;
    }
    if (c === '"') {
      out += c;
      inString = !inString;
      continue;
    }
    if (inString && code < 0x20) {
      switch (code) {
        case 0x08: out += '\\b'; break;
        case 0x09: out += '\\t'; break;
        case 0x0a: out += '\\n'; break;
        case 0x0c: out += '\\f'; break;
        case 0x0d: out += '\\r'; break;
        default:   out += '\\u' + code.toString(16).padStart(4, '0');
      }
      continue;
    }
    out += c;
  }
  return out;
}

/**
 * FR-C1 fallback: parse hook stdin into a full object. Tries native
 * JSON.parse first; falls back to a pure-node relaxed parser that
 * escapes literal control chars inside string contexts (the actual
 * hook payload shape Claude Code's harness emits — see
 * specs/wheel-as-runtime §FR-C1). Pure-node — no python dependency.
 *
 * Returns the parsed object on success, or null when both parses reject.
 */
export async function parseHookInputWithFallback(rawInput: string): Promise<unknown | null> {
  try {
    return JSON.parse(rawInput);
  } catch { /* fall through to relaxed parse */ }
  try {
    return JSON.parse(escapeJsonStringControlChars(rawInput));
  } catch {
    return null;
  }
}

/**
 * FR-C1 fallback: parse hook stdin and extract `tool_input.command`.
 * Tries native JSON.parse first; falls back to the relaxed parser
 * above for inputs containing literal control chars.
 */
export async function extractCommandWithFallback(rawInput: string): Promise<string> {
  const parsed = await parseHookInputWithFallback(rawInput);
  if (parsed && typeof parsed === 'object') {
    const cmd = (parsed as { tool_input?: { command?: string } })?.tool_input?.command;
    if (typeof cmd === 'string') return cmd;
  }
  if (parsed === null) {
    console.error('wheel post-tool-use: FR-C1 command extraction failed (both strict and relaxed JSON parsers rejected hook input)');
  }
  return '';
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
