#!/usr/bin/env node
// parse-test-yaml-env.mjs — pure-node parser for the test.yaml `env:` and
// `require-env:` blocks. Used by wheel-test-runner.sh to support running
// fixtures against 3rd-party models (Bedrock / Vertex / OpenRouter / etc.)
// via custom env vars injected per-test.
//
// Schema (additive — pre-existing test.yaml fields unchanged):
//
//   env:
//     KEY: value
//     OTHER_KEY: "quoted value"
//     SECRET: "${WHEEL_TEST_SECRET}"   # ${VAR} expanded from caller env
//
//   require-env:
//     - WHEEL_TEST_SECRET                # gate: SKIP test if any unset
//     - WHEEL_TEST_BASE_URL
//
// Substitution rules:
//   - "${VAR}" anywhere in a value is replaced with process.env.VAR.
//   - If VAR is unset AND the literal "${VAR}" appears in any env value,
//     the unset name is reported in `missingRequiredEnvs` (the call site
//     skips the test).
//   - "require-env" items are pure declarative — listed names MUST be
//     set in caller env or the test is skipped, regardless of whether
//     they appear in env: substitutions.
//
// Output (stdout, JSON):
//   {
//     "env": { "KEY": "resolved-value", ... },
//     "missingRequiredEnvs": ["VAR1", ...]
//   }
//
// On stderr / non-zero exit: parse error (e.g. malformed YAML block).
//
// Usage:
//   node parse-test-yaml-env.mjs <test-yaml-path>

import { readFileSync } from 'fs';

const path = process.argv[2];
if (!path) {
  process.stderr.write('parse-test-yaml-env.mjs: missing arg <test-yaml-path>\n');
  process.exit(2);
}

let raw;
try {
  raw = readFileSync(path, 'utf-8');
} catch (err) {
  process.stderr.write(`parse-test-yaml-env.mjs: cannot read ${path}: ${err.message}\n`);
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Block extraction. Walk lines; when we see `env:` or `require-env:`
// at column 0, gather subsequent lines that are MORE indented than the
// header (or empty/comments). The block ends at the next column-0 line
// or EOF.
// ---------------------------------------------------------------------------
function extractBlockLines(yaml, header) {
  const lines = yaml.split('\n');
  const out = [];
  let inBlock = false;
  for (const line of lines) {
    if (!inBlock) {
      if (line.match(new RegExp(`^${header}\\s*:\\s*$`))) {
        inBlock = true;
      }
      continue;
    }
    // End of block: a non-empty line that starts at column 0 (and is not
    // a comment) — that's the next top-level key.
    if (line.length > 0 && line[0] !== ' ' && line[0] !== '\t' && !line.startsWith('#')) {
      break;
    }
    out.push(line);
  }
  return out;
}

// Parse `env:` block — KEY: VALUE pairs.
function parseEnvBlock(blockLines) {
  const result = {};
  for (const raw of blockLines) {
    const line = raw.replace(/^\s+/, '');
    if (line === '' || line.startsWith('#')) continue;
    // Match `KEY: value` or `KEY: "value"` or `KEY: 'value'`.
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$/);
    if (!m) continue; // tolerate stray non-KV lines (e.g. anchors)
    const key = m[1];
    let value = m[2].trim();
    // Strip trailing inline comments (` # comment`) — but preserve `#` inside quotes.
    // Simple heuristic: if value starts with quote, find matching close; else split on " #".
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      const close = value.indexOf(quote, 1);
      if (close > 0) value = value.slice(1, close);
    } else {
      const cmtIdx = value.indexOf(' #');
      if (cmtIdx >= 0) value = value.slice(0, cmtIdx).trim();
    }
    result[key] = value;
  }
  return result;
}

// Parse `require-env:` block — list of `- NAME` items.
function parseRequireEnvBlock(blockLines) {
  const out = [];
  for (const raw of blockLines) {
    const line = raw.replace(/^\s+/, '');
    if (line === '' || line.startsWith('#')) continue;
    const m = line.match(/^-\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/);
    if (!m) continue;
    out.push(m[1]);
  }
  return out;
}

// Variable substitution: replace `${VAR}` with process.env.VAR. Track
// any VAR that's referenced but unset — those bubble up as missing
// requirements (same SKIP behavior as require-env).
function substitute(env, missing) {
  const resolved = {};
  for (const [key, value] of Object.entries(env)) {
    resolved[key] = value.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => {
      const v = process.env[name];
      if (v === undefined) {
        missing.add(name);
        return ''; // placeholder; caller skips the test anyway
      }
      return v;
    });
  }
  return resolved;
}

const envBlock = parseEnvBlock(extractBlockLines(raw, 'env'));
const requireEnv = parseRequireEnvBlock(extractBlockLines(raw, 'require-env'));

const missing = new Set();
const resolvedEnv = substitute(envBlock, missing);

// Add explicitly-required vars that are unset.
for (const name of requireEnv) {
  if (process.env[name] === undefined) missing.add(name);
}

process.stdout.write(JSON.stringify({
  env: resolvedEnv,
  missingRequiredEnvs: [...missing].sort(),
}) + '\n');
