// Hook output emitter with sentinel-file mirror.
//
// Why this exists: Claude Code's `--print` mode drops Stop-hook
// `additionalContext` when relaying to the orchestrator's transcript.
// The orchestrator sees "Stop hook feedback:\nBlocked by hook" with
// no actual instruction content, so it has no idea what to do next
// and falls back to investigating internals (which is forbidden) or
// stopping the workflow prematurely.
//
// Workaround: every wheel hook that returns `decision: 'block'` with
// `additionalContext` ALSO writes the additionalContext to
// `.wheel/.next-instruction.md`. The wheel-run skill + harness prompt
// instruct the orchestrator: "if a Stop hook blocks but the message
// is just 'Blocked by hook' with no actionable text, Read the file
// `.wheel/.next-instruction.md` for the literal next-step
// instructions." Read tool results survive `--print` mode intact.
//
// This is a Claude Code `--print` mode limitation; the wheel does the
// right thing in non-`--print` sessions where additionalContext is
// surfaced normally. The sentinel file is a parallel channel that
// works in both modes.
import { promises as fs } from 'fs';
import path from 'path';

const SENTINEL = path.join('.wheel', '.next-instruction.md');

interface EmittableHookOutput {
  decision?: 'approve' | 'block';
  additionalContext?: string;
  [key: string]: unknown;
}

/**
 * Single emit point for hook responses. Writes the JSON response to
 * stdout (the only thing Claude Code reads) AND, when the response
 * carries `additionalContext`, mirrors that text to the sentinel file
 * so an orchestrator running in `--print` mode can recover the
 * instruction by Reading the file.
 *
 * Sentinel writes are best-effort: an `fs.writeFile` failure must NOT
 * suppress the stdout response (which Claude Code requires). Any
 * write error is logged to stderr and swallowed.
 */
export async function emitHookOutput(output: EmittableHookOutput): Promise<void> {
  // 1. Always emit stdout — this is the contract with Claude Code.
  console.log(JSON.stringify(output));

  // 2. Mirror additionalContext to the sentinel file when present.
  //
  // Stable timestamp behaviour: if the new additionalContext body is
  // BYTE-IDENTICAL to the previous sentinel body (same stuck-state),
  // do NOT rewrite the file. This keeps mtime stable across repeated
  // identical hook fires so an orchestrator polling the sentinel can
  // detect "nothing has changed since my last read" by mtime check
  // alone. Without this, every Stop hook re-emits the file with a
  // fresh timestamp even when the content is unchanged, and the
  // orchestrator can't tell repeats from progress.
  const ctx = output.additionalContext;
  if (typeof ctx !== 'string' || ctx.length === 0) return;
  try {
    const dir = path.dirname(SENTINEL);
    await fs.mkdir(dir, { recursive: true });
    let priorBody = '';
    try { priorBody = await fs.readFile(SENTINEL, 'utf-8'); } catch { /* missing — first write */ }
    // Strip the timestamp line from the prior body for comparison;
    // we only care about whether the INSTRUCTION TEXT is the same.
    const priorWithoutStamp = priorBody.replace(/^<!-- wheel hook instruction — [^>]+ -->\n\n/, '');
    const newWithoutStamp = `${ctx}\n`;
    if (priorWithoutStamp === newWithoutStamp) return; // no change — skip write

    const stamp = new Date().toISOString();
    const body = `<!-- wheel hook instruction — ${stamp} -->\n\n${ctx}\n`;
    await fs.writeFile(SENTINEL, body);
  } catch (err) {
    // Best-effort. Log and proceed.
    console.error('wheel: sentinel write failed:', String(err));
  }
}
