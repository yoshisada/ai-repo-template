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

4. **CRITICAL: stream-json stdin MUST be a pipe, NOT a regular-file redirect** (discovered Phase F 2026-04-23). Claude Code v2.1.119 silently emits ZERO envelopes when stdin is a regular file via `< file.json` — no init, no assistant, no result, exit 0, no error. The same envelope stream PIPED via `cat file.json | claude ...` works correctly. `claude-invoke.sh` now pipes via `cat "$env_stream" | exec claude ...`. If the first seed test had not caught this, we'd have shipped a harness that silently passes every test (every subprocess would exit 0 with nothing written, making assertion.sh the sole arbiter — exactly the failure mode this PRD is supposed to prevent). This is the single most load-bearing discovery of the implementation.

5. **Up-front multi-envelope semantics CONFIRMED WORKING** in Phase F: the hygiene-backfill seed test sends ONE user envelope ("run backfill twice") and the subprocess correctly processes it, running the skill twice (producing two distinct `.kiln/logs/prd-derived-from-backfill-<ts>.md` files), then emits a `{"type":"result",...}` envelope and exits. Multi-envelope streams via pipe-fed stdin Just Work with --input-format=stream-json.

6. **Seed test wall-clock**: `/kiln:kiln-hygiene backfill` twice end-to-end = ~1m30s including 30s watcher-poll slack. Acceptable per NFR-006.

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
- [Phase D] — **done (T015)**. Wrote `plugin-kiln/skills/kiln-test/SKILL.md` with the three-form invocation table, consumer contract, `.kiln/test.config` override docs, env-var table for assertions.sh, and out-of-scope list. Body delegates to `"${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh" $ARGUMENTS`. Zero repo-relative `plugin-kiln/scripts/...` paths per NFR-001.
- [Phase E] — **done (T016)**. `.kiln/test.config` key docs + `claude` on PATH requirement + example config in SKILL.md; `config-load.sh` error surface already covered via `bail_out` in kiln-test.sh Phase A. No code changes required beyond SKILL.md additions.
- [Phase F — seed tests] — **done (T017, T018)**. BOTH seed tests PASS via real Claude subprocesses:
  1. `kiln-distill-basic` — single theme engineered so Step 3 scope prompt is skipped; PRD generated at `docs/features/<date>-<slug>/PRD.md` with `derived_from:` frontmatter referencing both fixtures; assertion passes. End-to-end ~2m.
  2. `kiln-hygiene-backfill-idempotent` — one initial-message envelope asks the subprocess to run `/kiln:kiln-hygiene backfill` twice; both `.kiln/logs/prd-derived-from-backfill-*.md` logs written; hunk count stable (idempotence holds per FR-010 file-state semantics); assertion passes. End-to-end ~1m30s.
  3. **Full plugin suite**: `/kiln:kiln-test kiln` → `TAP version 14\n1..2\nok 1 - kiln-distill-basic\nok 2 - kiln-hygiene-backfill-idempotent\n`, exit 0, 3m31s wall-clock.
  4. **Critical discovery** (called out above in Watchouts #4): the pipe-vs-redirect stdin behavior of `claude --print --input-format=stream-json`. Without the pipe-fix in claude-invoke.sh, both tests produced empty transcripts and would have wasted the whole harness. This is exactly the class of silent-pass regression the PRD exists to prevent — caught by running the seed tests, which is exactly the briefing's "A test that is written but never run is the exact problem this PRD is supposed to solve."
- [Phase G — CLAUDE.md] — **done (T019)**. Added `/kiln:kiln-test [plugin] [test]` entry under "Other" in Available Commands, naming all three invocation forms, the stream-json flag set actually used, the verdict report + retained scratch paths, the v1 substrate scope, and pointers to the seed tests.
- [Phase H — SMOKE.md] — **done (T020)**. Wrote `specs/plugin-skill-test-harness/SMOKE.md` with 4 executable blocks (A: distill-basic standalone; B: hygiene-backfill-idempotent standalone; C: full plugin suite; D: TAP determinism across two runs). Block B executed standalone to verify the grep invariants fire correctly — `BLOCK B PASS`. Closes the long-standing retrospective gap: the harness has its own executable smoke test.

## Seed test failures encountered during development

- [will be populated as seed tests are written + debugged]
