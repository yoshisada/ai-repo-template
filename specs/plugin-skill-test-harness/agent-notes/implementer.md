# Implementer Friction Notes

**Agent**: implementer
**Task**: #2 — Implement plugin-skill-test-harness
**Branch**: `build/plugin-skill-test-harness-20260424`
**Date**: 2026-04-23 (started)

## CLI flag verification (Phase A pre-gate)

**Claude Code version used for this build**: `2.1.119 (Claude Code)`

**PRD-assumed flags vs. v2.1.119 reality**:

| Assumed | Exists? | Replacement |
|---|---|---|
| `--plugin-dir <path>` | ✅ | — |
| `--headless` | ❌ | `-p` / `--print` (with `--verbose` required for stream-json output) |
| `--dangerously-skip-permissions` | ✅ | — |
| `--initial-message <text>` | ❌ | First stream-json user envelope on stdin |

**Resolution**: BLOCKER-001 filed → team-lead picked Option A → plan.md D6 + contracts/interfaces.md §7.2 + §3 + §5 updated → blocker closed. See commit "spec(contract): pivot to stream-json for multi-turn skill invocation (resolves CLI blocker)".

## Empirically-verified stream-json envelope shapes (v2.1.119)

Probe command (from `/tmp/kiln-cli-probe`):

```bash
echo '{"type":"user","message":{"role":"user","content":"Reply with exactly: PROBE_OK"}}' \
  | claude --print --verbose --input-format=stream-json --output-format=stream-json \
           --dangerously-skip-permissions --bare
```

**Output envelopes observed (NDJSON, one per line, in order)**:

```jsonc
{"type":"system","subtype":"init","cwd":"...","session_id":"<uuidv4>","tools":[...],"mcp_servers":[...],"model":"claude-sonnet-4-6","permissionMode":"bypassPermissions","slash_commands":[...],"apiKeySource":"none","claude_code_version":"2.1.119","plugins":[...],"agents":[...],"skills":[...],"uuid":"..."}

{"type":"assistant","message":{"id":"...","role":"assistant","content":[{"type":"text","text":"..."}],"stop_reason":"...","usage":{...}},"session_id":"...","uuid":"...","error":"..."}

{"type":"result","subtype":"success","is_error":<bool>,"duration_ms":N,"duration_api_ms":N,"num_turns":N,"result":"<final-text>","session_id":"...","total_cost_usd":N,"usage":{...},"terminal_reason":"completed","uuid":"..."}
```

**Input envelope (stdin, NDJSON)**:

```jsonc
{"type":"user","message":{"role":"user","content":"<text>"}}
```

## Watchouts discovered during CLI probe

1. **`--verbose` is MANDATORY** with `--print --output-format=stream-json`. The CLI hard-errors otherwise:

   ```
   Error: When using --print, --output-format=stream-json requires --verbose
   ```

   `claude-invoke.sh` MUST include `--verbose`. (This was not in the PRD.)

2. **`--bare` breaks auth** by skipping keychain reads. Tests against an authenticated user's session MUST NOT use `--bare`. We rely on the default auth path.

3. **`timeout(1)` is not on macOS by default**. The watcher's own termination via SIGTERM is the only reliable stall-termination mechanism — FR-008's "no hard caps" matches what's actually available.

4. **Up-front multi-envelope semantics require Phase B validation**. My CLI probe only sent ONE user envelope (constrained by budget). The design queues all answers before stdin EOF and trusts the runtime to process them in order. If Phase B's trivial pass-test reveals the runtime processes only the first envelope, I'll file BLOCKER-002 and we revisit.

## Uncertainties carried forward

- [will be populated as Phase A/B/C work surfaces them]

## Phase-by-phase friction log

- [Phase A]: pending
- [Phase B]: pending
- [Phase C]: pending
- [Phase D]: pending
- [Phase E]: pending
- [Phase F — seed tests]: pending
- [Phase G — CLAUDE.md]: pending
- [Phase H — SMOKE.md]: pending

## Seed test failures encountered during development

- [will be populated as seed tests are written + debugged]
