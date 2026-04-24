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

- [Phase A] — **done (T001..T007)**. Two notable frictions:
  1. **Subshell-swallowed bail-out**: My first `kiln-test.sh` had `bail_out()` emit the TAP `Bail out!` line to stdout, and called it from inside `$(auto_detect_plugin ...)`. Result: the line was captured into the command substitution and never reached the terminal; callers just saw `EXIT=2` with no explanation. Refactored so helpers that *may* bail write to stderr + return non-zero; the top-level caller turns that into the Bail out! line. Contract convention to carry forward: **never call `bail_out` from inside a command substitution**; always at top-level.
  2. **Multi-plugin auto-detect**: this repo itself has 5 `plugin-*/` dirs. Auto-detect correctly bails with a plugin-list (expected per spec Edge Cases), but I noticed that this means the seed tests can NEVER use the zero-arg form inside this source repo — SMOKE.md blocks must pass `kiln` explicitly. Will update SMOKE.md accordingly in Phase H.

  Phase A checkpoint verified: empty `plugin-kiln/tests/` → `TAP version 14\n1..0\n` exit 0; probe test → `ok 1 - phase-a-probe # SKIP substrate-not-yet-wired` exit 2; invalid test.yaml → SKIP with validation diagnostic; nonexistent plugin/test → Bail out!.
- [Phase B] — **done (T008..T011)**. Notable frictions:
  1. **`--verbose` mandatory with stream-json output** — discovered during CLI probe. `claude-invoke.sh` includes it and the CLI-drift self-check greps for it.
  2. **No jq/yq dependency** — I deliberately wrote the envelope encoder in awk (+ perl-opt for robust JSON-escape on the initial-message file) so consumers don't need jq. Verified the output round-trips through `python3 json.loads` with tabs, embedded double quotes, and embedded newlines intact.
  3. **Fake `claude` for Phase B self-test** — rather than burn tokens on every Phase B checkpoint run, I wrote a tiny `FAKEBIN/claude` that responds to `--help` with the expected flag set and echoes stdin to a file. This let me verify the full end-to-end fixture-seed → spawn-subprocess → assertions → emit-TAP flow without real Claude invocations. The real-Claude validation is deferred to Phase F seed-test execution.
  4. **Phase B verification outcomes**:
     - Trivial pass test: `ok 1 - phase-b-trivial-pass`, scratch dir deleted, exit 0 ✅
     - Trivial fail test: `not ok 1 - phase-b-trivial-fail` with complete YAML diagnostic (classification, scratch-uuid, retained path, verdict + transcript paths, assertion stdout/stderr), scratch retained, exit 1 ✅
     - `.kiln/logs/` populated with `kiln-test-<uuid>-transcript.ndjson` + `kiln-test-<uuid>-scratch.txt` ✅
- [Phase C] — **done (T012..T014)**. Notable decisions:
  1. **Pure-bash watcher for v1**: The classification rules (healthy/stalled/failed) are purely mechanical file-state + timestamp checks. No LLM invocation required. I implemented `watcher-runner.sh` as a pure-bash polling loop that reads `watcher-poll.sh` snapshots and classifies directly. The `plugin-kiln/agents/test-watcher.md` agent spec documents the rules authoritatively and is the extension point for a future LLM-assisted classifier when rule-based triage proves insufficient. This reconciles contracts §7.9 ("Spawns the test-watcher agent via the Task tool") with the harness's bash-native reality — the contract stays additive-compatible when/if LLM classification becomes the default.
  2. **Background substrate + foreground watcher**: `kiln-test.sh` now backgrounds `dispatch-substrate.sh` and foregrounds `watcher-runner.sh`. The watcher polls, classifies, and on `stalled` sends SIGTERM to the substrate process group. `wait $substrate_pid` then returns and the harness checks `verdict.json` for stalled classification BEFORE the subprocess exit-code comparison — a stalled-then-SIGTERMed subprocess exits with non-zero (143), and without the verdict check we'd misreport that as "failed exit-code mismatch" instead of "stalled".
  3. **Phase C verification**:
     - Trivial pass via fake claude: `ok 1 - phase-c-watcher-pass`, ~2.5s total (poll_interval=2s).
     - Hanging fake claude (stall_window=6s, poll_interval=2s): `not ok 1 - phase-c-watcher-stalled` with `classification: "stalled"`, scratch retained, ~9s total (well under the contract's `stall_window + poll_interval` ≈ 8s gate; slight slack for SIGTERM + wait).
     - Verdict JSON emitted to `.kiln/logs/kiln-test-<uuid>-verdict.json` with complete payload (timestamps, last_50_lines, scratch_files, result_envelope).
     - Verdict MD human-readable report at `.kiln/logs/kiln-test-<uuid>.md` with scratch-uuid/classification/transcript.
  4. **Subprocess-exit latency caveat**: Fast trivial tests (<1s) add up to `poll_interval` wall-clock because the watcher sleeps between ticks. For real seed tests this is noise; for self-test iteration I ship a short `.kiln/test.config` override (2s poll / 60s stall) in the dev workflow and let defaults (30s/300s) apply in production.
- [Phase D]: pending
- [Phase E]: pending
- [Phase F — seed tests]: pending
- [Phase G — CLAUDE.md]: pending
- [Phase H — SMOKE.md]: pending

## Seed test failures encountered during development

- [will be populated as seed tests are written + debugged]
