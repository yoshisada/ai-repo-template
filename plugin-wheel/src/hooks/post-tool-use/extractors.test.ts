// FR-C1 pure-node relaxed JSON parser coverage. Replaces the python3
// strict=False fallback the hook used to exec — wheel has zero runtime
// python dependency now, so these tests are the canonical proof that
// the literal-control-char shape Claude Code's harness emits is parseable
// with node-only logic.
import { describe, it, expect } from 'vitest';
import {
  parseHookInputWithFallback,
  extractCommandWithFallback,
} from './extractors.js';

describe('parseHookInputWithFallback (pure-node FR-C1 fallback)', () => {
  it('parses compliant JSON via the strict fast-path', async () => {
    const raw = JSON.stringify({
      tool_input: { command: 'echo hi\necho bye' },
    });
    const out = await parseHookInputWithFallback(raw);
    expect(out).toEqual({ tool_input: { command: 'echo hi\necho bye' } });
  });

  it('parses payload with literal newline inside a string value', async () => {
    // The actual shape Claude Code's harness emits: tool_input.command
    // contains raw 0x0A bytes inside the JSON string. Strict JSON.parse
    // rejects ("Bad control character in string literal").
    const raw = '{"tool_input":{"command":"line1\nline2\nline3"}}';
    const out = await parseHookInputWithFallback(raw);
    expect(out).toEqual({ tool_input: { command: 'line1\nline2\nline3' } });
  });

  it('parses payload with literal tab + carriage return inside string', async () => {
    const raw = '{"tool_input":{"command":"a\tb\rc"}}';
    const out = await parseHookInputWithFallback(raw);
    expect(out).toEqual({ tool_input: { command: 'a\tb\rc' } });
  });

  it('handles already-escaped sequences alongside literal control chars', async () => {
    // Mix: \n is an escape sequence (literal backslash-n), \t is a real
    // tab byte. Strict parse rejects on the tab; relaxed parse must
    // preserve both: the escape sequence becomes a real newline, the
    // tab byte becomes a real tab.
    const raw = '{"tool_input":{"command":"escaped\\nactual\there"}}';
    const out = await parseHookInputWithFallback(raw);
    expect(out).toEqual({ tool_input: { command: 'escaped\nactual\there' } });
  });

  it('returns null when both parsers reject (truly malformed)', async () => {
    const raw = '{"unclosed":';
    const out = await parseHookInputWithFallback(raw);
    expect(out).toBeNull();
  });

  it('does not mis-escape control bytes that are between tokens', async () => {
    // Newlines BETWEEN structural tokens are legal JSON whitespace —
    // strict parse already accepts. The relaxed parser is only used as
    // a fallback when strict fails, so this case verifies strict path.
    const raw = '{\n  "tool_input": {\n    "command": "ls"\n  }\n}';
    const out = await parseHookInputWithFallback(raw);
    expect(out).toEqual({ tool_input: { command: 'ls' } });
  });
});

describe('extractCommandWithFallback', () => {
  it('extracts command from compliant JSON', async () => {
    const raw = JSON.stringify({ tool_input: { command: 'echo ok' } });
    expect(await extractCommandWithFallback(raw)).toBe('echo ok');
  });

  it('extracts multi-line command from literal-newline payload', async () => {
    const raw = '{"tool_input":{"command":"echo a\necho b\necho c"}}';
    expect(await extractCommandWithFallback(raw)).toBe('echo a\necho b\necho c');
  });

  it('returns empty string when tool_input.command is absent', async () => {
    const raw = '{"tool_input":{}}';
    expect(await extractCommandWithFallback(raw)).toBe('');
  });

  it('returns empty string on totally malformed input (logs but does not throw)', async () => {
    const raw = '{not json';
    expect(await extractCommandWithFallback(raw)).toBe('');
  });
});
