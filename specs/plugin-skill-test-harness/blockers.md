# Implementation Blockers

**Feature**: plugin-skill-test-harness
**Branch**: `build/plugin-skill-test-harness-20260424`
**Filed by**: implementer
**Filed**: 2026-04-23

---

## BLOCKER-001: PRD-assumed Claude CLI flags do not exist in v2.1.119

**Status**: ✅ RESOLVED 2026-04-23 — team-lead picked Option A (pivot to `--print --verbose --input-format=stream-json --output-format=stream-json`). Contract + plan updated in the commit that accompanies this file. See plan.md D6 for the full rationale and the verified envelope shapes; see contracts/interfaces.md §7.2 + §3 + §5 for the updated script signatures and watcher classification. Note that the originally-planned FIFO-based mid-stream answer pump has also been simplified out — scripted answers are queued up-front as stream-json user envelopes before stdin EOF, and the `paused` watcher classification is removed. Empirical-validation gate: Phase B's first trivial-pass test is the point at which the up-front-envelopes semantics are verified; if the runtime behaves differently than designed, a follow-on BLOCKER-002 will be filed.

### Verification command

```bash
claude --version
# 2.1.119 (Claude Code)

claude --help 2>&1 | grep -E "plugin-dir|headless|dangerously-skip-permissions|initial-message"
```

### Findings

| PRD/contracts assumption | CLI v2.1.119 reality |
|---|---|
| `--plugin-dir <path>` | ✅ EXISTS — `--plugin-dir <path>` (repeatable) |
| `--headless` | ❌ **DOES NOT EXIST** |
| `--dangerously-skip-permissions` | ✅ EXISTS |
| `--initial-message <text>` | ❌ **DOES NOT EXIST** |

### What replaces the missing flags

**Replacement for `--headless`**: The CLI has two non-interactive modes:

- `-p` / `--print` — "Print response and exit (useful for pipes). Note: The workspace trust dialog is skipped when Claude is run with the -p mode."
- `--bare` — "Minimal mode: skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery. Sets CLAUDE_CODE_SIMPLE=1."

`--print` is the closest analogue — it's the documented non-interactive flag. **However**, `--print` is one-shot ("print response and exit"); it does NOT support an interactive multi-turn session that can be paused and answered mid-stream. This directly contradicts the harness design (FR-010: watcher detects `paused`, driver writes next answer to subprocess stdin).

**Replacement for `--initial-message <text>`**: The initial prompt is passed as a positional `prompt` argument:

```
Usage: claude [options] [command] [prompt]
Arguments:
  prompt    Your prompt
```

Or via stdin when used with `--print --input-format=stream-json` (streaming JSON envelopes).

### Why this is a hard blocker, not a documentation fix

The architectural premise of the harness (per spec.md FR-009 + FR-010 + plan.md D6 + contracts/interfaces.md §7.2) is:

1. Spawn one persistent `claude` subprocess per test.
2. Watcher polls it.
3. On `paused` classification, driver writes the next `answers.txt` line to the subprocess's stdin.
4. Subprocess processes the answer and either emits more output or pauses again.
5. Repeat until exit.

This requires a persistent, mid-stream-promptable, non-interactive (no TTY decoration) Claude session. None of the v2.1.119 flags directly support that:

- `--print` is one-shot — exits after the first response. Cannot accept follow-up answers mid-session.
- `--input-format=stream-json` (with `--print`) accepts a stream of JSON-wrapped user messages — this MIGHT be the right mechanism for FR-010, but it is NOT a one-line flag swap and the contract for it (envelope shape, ordering rules, when the subprocess closes vs. waits for more) is not defined in the contracts/interfaces.md and is not what the PRD assumed.
- `--bare` does not change the interactive vs non-interactive axis — it skips hooks/LSP/auto-memory but still expects a TTY for interactive sessions.

### Options for unblocking

**Option A — Re-architect FR-009/FR-010 around `--print --input-format=stream-json --output-format=stream-json`**

- Each test becomes one stream-json invocation.
- `inputs/initial-message.txt` becomes the first stream-json envelope.
- `inputs/answers.txt` lines become subsequent envelopes pushed to stdin when watcher classifies `paused`.
- Watcher's `paused` detection regex (contracts §3) needs to read stream-json transcript instead of raw stdout — different parser.
- `claude-invoke.sh` (contracts §7.2) signature stays roughly the same but flag set changes from `--headless --initial-message <text>` to `--print --input-format=stream-json --output-format=stream-json` with the initial message as the first stdin envelope.
- contracts/interfaces.md §7.2 + §3 + plan.md D6 all need updates BEFORE I write code (Article VII).

**Option B — Skip multi-turn for v1; one-shot only**

- Drop FR-010 from v1; document `paused for input` and `answers.txt` as v2 (a follow-on PRD when the stream-json approach is validated).
- v1 substrate spawns `claude --plugin-dir <root> --dangerously-skip-permissions --print "$(cat inputs/initial-message.txt)"`.
- Seed test #1 (`kiln-distill-basic`) currently relies on answering the "which theme?" prompt — would need to be reworked to either auto-answer via the initial message body or be replaced with a non-prompting seed test.
- Seed test #2 (`kiln-hygiene-backfill-idempotent`) doesn't prompt the user, so it survives unchanged.
- Lower risk; ships faster; the hard "watcher replaces hard timeouts" architectural differentiator (User Story 3) survives because watcher still classifies `stalled` / `failed` — it just won't see `paused` for v1.

**Option C — Pin to an older Claude Code build that DOES have `--headless`**

- I can find no evidence `--headless` ever existed in Claude Code; grep of the v2.1.119 help shows only `-p`/`--print` and `--bare`. The PRD authors may have been thinking of the SDK / a different binary. This option is likely a dead end but flagging for completeness.

### My recommendation

**Option A**, because it preserves all v1 FRs including the multi-turn behavior that motivates the watcher's `paused` classification (User Story 3 acceptance scenario 3). The contract update is small (flag list in §7.2 + transcript parser in §3 + plan.md D6 rationale). Option B sacrifices a stated FR.

If team-lead picks **Option A**:
- I'll update plan.md D6 + contracts §3 + §7.2 first (Article VII), commit that update as "plan: pivot from --headless to --print stream-json (CLI drift fix)".
- Then proceed with Phase A as planned.

If team-lead picks **Option B**:
- I'll update spec.md to mark FR-010 deferred + plan.md D6 + contracts §6 § "Exhaustion / Missing file" semantics + remove the `paused` classification from the watcher.
- Drop User Story 3 acceptance scenario 3 + SC related to scripted answers.
- Rework seed test #1 to be non-prompting OR swap to `/kiln:kiln-constitution` (per specifier's A3 fallback note).

### Status

**WAITING FOR TEAM-LEAD GUIDANCE.** Will resume Phase A immediately on receipt of A/B/C decision (or alternative).

---
