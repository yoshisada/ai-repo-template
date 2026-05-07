// _extract-command.mjs — pure-node FR-C1 fallback for shell shims that
// need to extract `tool_input.command` from a hook payload that may
// contain literal U+0000..U+001F bytes inside string values.
//
// Reads stdin, parses with JSON.parse first, then with a relaxed
// parser that escapes control bytes within string contexts. Writes the
// command (or empty string) to stdout. Replaces the previous python3
// strict=False fallback — wheel has zero runtime python dependency.
//
// Used by hooks/block-state-write.sh. Mirrors the relaxed parser in
// dist/hooks/post-tool-use/extractors.js (single source of truth lives
// in src/hooks/post-tool-use/extractors.ts; this file is a small
// shell-callable copy for hooks that don't go through the TS entry).

let buf = '';
process.stdin.setEncoding('utf-8');
process.stdin.on('data', (d) => { buf += d; });
process.stdin.on('end', () => {
  let parsed;
  try {
    parsed = JSON.parse(buf);
  } catch {
    try {
      parsed = JSON.parse(escapeJsonStringControlChars(buf));
    } catch {
      process.exit(2);
    }
  }
  const cmd = (parsed && typeof parsed === 'object'
    && parsed.tool_input && typeof parsed.tool_input.command === 'string')
    ? parsed.tool_input.command
    : '';
  process.stdout.write(cmd);
});

function escapeJsonStringControlChars(raw) {
  let inString = false;
  let escape = false;
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    const code = raw.charCodeAt(i);
    if (escape) { out += c; escape = false; continue; }
    if (c === '\\') { out += c; escape = true; continue; }
    if (c === '"') { out += c; inString = !inString; continue; }
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
