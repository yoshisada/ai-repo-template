# Implementation Plan: Plugin Skill Test Harness

**Branch**: `build/plugin-skill-test-harness-20260424`
**Date**: 2026-04-24
**Spec**: [spec.md](./spec.md)
**Parent PRD**: [docs/features/2026-04-24-plugin-skill-test-harness/PRD.md](../../docs/features/2026-04-24-plugin-skill-test-harness/PRD.md)

## Summary

Ship a single user-facing skill `/kiln:kiln-test` plus a small set of supporting scripts and one watcher agent. The skill discovers a plugin's test directories, for each test creates an isolated `/tmp/kiln-test-<uuid>/` scratch dir, copies fixtures in, spawns a real `claude --plugin-dir <plugin-root> --headless --dangerously-skip-permissions` subprocess (one per test — no pooling in v1), watches the subprocess with a haiku-model classifier agent that replaces hard timeouts, dispatches scripted answers from `answers.txt` when the classifier sees a `paused` state, runs `assertions.sh` against the final scratch-dir state, emits TAP v14 output with YAML diagnostic blocks, and cleans up or retains the scratch dir based on outcome. V1 ships one substrate driver (`plugin-skill`); the substrate dispatcher is factored as an abstraction to make follow-on substrate PRDs additive.

## Technical Context

**Language/Version**: Bash 5.x (harness scripts), Markdown (SKILL.md + agent.md + test metadata as YAML)
**Primary Dependencies**: `claude` CLI (on PATH), `jq` (YAML/JSON parsing in bash via `yq` or equivalent if available, else grep-based extraction as fallback), `uuidgen`, POSIX `find` + `sha256sum`, standard POSIX utilities (`sed`, `grep`, `awk`, `date`, `stat`)
**Storage**: File-based only — scratch dirs under `/tmp/kiln-test-<uuid>/`; verdict reports at `.kiln/logs/kiln-test-<uuid>.md`; scratch snapshots at `.kiln/logs/kiln-test-<uuid>-scratch.txt`; optional overrides via `.kiln/test.config`
**Testing**: The harness's own tests are executable fixtures under `plugin-kiln/tests/` (two seed tests per FR-015) plus a `SMOKE.md` meta-test that invokes the harness against those seed tests and checks exit codes
**Target Platform**: macOS + Linux (anywhere `claude` runs); no Windows support
**Project Type**: CLI/skill — Claude Code plugin skill invoked by a human via `/kiln:kiln-test`
**Performance Goals**: ~5-10s subprocess startup per test (inherent); watcher poll every 30s; stall window 5m. Not latency-sensitive.
**Constraints**: No new runtime deps, no MCP calls, no `gh` calls. Portable: `${WORKFLOW_PLUGIN_DIR}/...` in SKILL.md (NFR-001). Deterministic TAP output (NFR-003).
**Scale/Scope**: A plugin repo ships O(10-50) tests; full-run wall-clock ~2-5 minutes. Single-named-test run for dev iteration is always <30s of harness overhead.

## Constitution Check

*GATE: Must pass before implementation. Re-check after design.*

- **Article I (Spec-First)**: spec.md exists and is the source of truth. ✅
- **Article II (80% Coverage)**: Harness is bash + markdown; the "tests" for this feature are executable fixtures (two seed tests + SMOKE.md). The constitutional 80% coverage gate applies to compiled-language code; bash harness tests are executed via the SMOKE.md meta-fixtures. Documented in Complexity Tracking below.
- **Article III (PRD as Source of Truth)**: docs/features/2026-04-24-plugin-skill-test-harness/PRD.md is the parent. Spec FRs map 1:1 to PRD FRs. ✅
- **Article IV (Hooks Enforce Rules)**: Not a hook-modifying feature. Existing hooks remain untouched. ✅
- **Article V (E2E Testing)**: The seed tests ARE the E2E tests — they spawn real `claude` subprocesses against real fixtures. ✅
- **Article VI (Small, Focused Changes)**: 8 phases, 15-18 tasks, no file over 500 lines. ✅
- **Article VII (Interface Contracts)**: See `contracts/interfaces.md` — all helper-script signatures, YAML/JSON schemas, and grammar rules are locked. ✅
- **Article VIII (Incremental Completion)**: Tasks marked `[X]` immediately per phase; commit per phase. ✅

## Decisions (Lock all 7 PRD Open Questions)

All seven PRD open questions are LOCKED here. Changing any decision after this point requires a `/kiln:kiln-fix` run that updates plan.md first.

### D1 — Canonical test discovery path *(resolves PRD OQ1)*

**Decision**: `plugin-<name>/tests/<test-name>/`

**Rationale**: Co-locates tests with the source they test; matches pytest/jest conventions where a developer editing the skill source sees the tests without leaving the source tree. Does not conflate with `.kiln/`, which is for runtime state (reports, scratch snapshots). Alternative `.kiln/harness/tests/` was rejected for hiding tests away from the source they verify. Alternative `tests/plugin-<name>/` was rejected for fragmenting tests across repo root in a multi-plugin monorepo.

**Override**: `.kiln/test.config` key `discovery_path` MAY override to a custom glob (e.g., `tests/**/`), but this is an escape hatch, not the expected flow.

### D2 — Answer-file format *(resolves PRD OQ2)*

**Decision**: `inputs/answers.txt`, one line per prompt, consumed in FIFO order by the driver when the watcher reports `paused for input`.

**Rationale**: Simplest format that covers the motivating use case (scripted answers to skill prompts). Prompt-regex matching (`answers.yaml`) was considered but deferred to a follow-on — empirical experience with the v1 format will tell us whether prompt drift is a real problem. Overly structured formats (JSONL) add parsing cost for no v1 value.

**Behavior when exhausted/missing**: Test fails with a diagnostic naming the unanswered prompt (FR-010).

### D3 — Watcher classification thresholds *(resolves PRD OQ3)*

**Decision**: `stall_window = 5 minutes`, `poll_interval = 30 seconds`. Both overridable via `.kiln/test.config` keys `watcher_stall_window_seconds` and `watcher_poll_interval_seconds`, and per-test via `test.yaml` key `timeout-override` (overrides stall window only).

**Rationale**: 5m is empirically the shortest interval that doesn't false-positive on skill bodies that include a `gh` call or an `npm install`-shaped subcommand. 30s poll keeps the watcher's own cost bounded while still giving sub-minute responsiveness to `paused` states. Per-test override handles exceptional cases (e.g., a long-running `/kiln:kiln-build-prd` fixture).

### D4 — TAP output shape *(resolves PRD OQ4)*

**Decision**: TAP version 14 with YAML diagnostic blocks for `not ok` results.

**Rationale**: Widely supported by `prove`, `tap-parser`, and `node-tap`. Human-readable. YAML diagnostic blocks support multi-line error messages (missing-frontmatter, diff-hunk lists, etc.) without escape-hell. Alternative JSON-lines was rejected for losing TAP tooling compatibility.

### D5 — Watcher agent location *(resolves PRD OQ5)*

**Decision**: `plugin-kiln/agents/test-watcher.md`.

**Rationale**: Matches the location of every other kiln agent (qa-engineer, debugger, smoke-tester, spec-enforcer, test-runner, ux-evaluator, prd-auditor, continuance, qa-reporter). Nesting under `plugin-kiln/skills/kiln-test/agents/` was rejected — breaks the pattern that agents are top-level citizens discoverable by `/agents`.

**Model**: `haiku` (cost-optimized; the watcher's job is classification, not generation).

### D6 — Subprocess invocation flags + multi-turn mechanism *(resolves PRD OQ6 + CLI-drift blocker)*

**Decision**: Spawn `claude --print --verbose --input-format=stream-json --output-format=stream-json --dangerously-skip-permissions --plugin-dir <plugin-root>`. Multi-turn answers from `answers.txt` are written up-front as a sequence of stream-json user envelopes on stdin, followed by EOF. `--dangerously-skip-permissions` keeps the session from blocking on tool-use prompts; scratch-dir isolation is the safety boundary.

**Rationale (incl. blocker-resolution context, 2026-04-23)**: The originally-assumed PRD flags `--headless` and `--initial-message` do not exist in Claude Code v2.1.119 (see `blockers.md` BLOCKER-001 → RESOLVED). The non-interactive mode is `--print`; multi-turn input arrives via `--input-format=stream-json` (one NDJSON envelope per user message on stdin). `--verbose` is required by the CLI when `--output-format=stream-json` is set with `--print`. `--bare` is NOT used because it skips keychain reads and breaks Anthropic auth.

**Why up-front envelopes instead of FIFO mid-stream pump**: Simpler. The runtime processes stream-json input envelopes in order; closing stdin cleanly terminates the session. There is no need for the watcher to detect a `paused` state and push the next answer mid-stream — all answers are pre-known (from `answers.txt`) and queued at process start. This eliminates a FIFO, eliminates the `paused` classification's need to gate stdin writes, and removes a concurrency hazard. Trade-off: if a skill prompts in a different order than `answers.txt` expects, the test fails as `stalled` or `failed` (assistant didn't consume the queued answer in time, or model output didn't match the test's expectations). That's an acceptable failure mode — it's a loud test failure, not silent breakage.

**Watcher classification update (cascading from D6)**: The `paused` classification is removed. Classifications are: `healthy` (assistant envelopes arriving OR scratch writes advancing), `stalled` (no envelope AND no scratch write for `stall_window`), `failed` (result envelope with `is_error:true` whose exit code doesn't match `test.yaml`'s `expected-exit`). FR-010's "answers fed mid-stream" semantics are reframed as "answers queued up-front; missing answers manifest as stalled or failed downstream".

**Envelope shapes (verified empirically against v2.1.119 on 2026-04-23)**:

```jsonc
// IN  (one line per envelope on stdin):
{"type":"user","message":{"role":"user","content":"<text>"}}

// OUT (NDJSON on stdout in this order):
{"type":"system","subtype":"init","session_id":"...","cwd":"...","tools":[...],"model":"...",...}
{"type":"assistant","message":{"id":"...","role":"assistant","content":[{"type":"text","text":"..."}],"stop_reason":"...","usage":{...}},"session_id":"...","uuid":"..."}
// ... more assistant envelopes (one per turn) ...
{"type":"result","subtype":"success","is_error":<bool>,"duration_ms":N,"num_turns":N,"result":"...","total_cost_usd":N,"terminal_reason":"completed",...}
```

**Empirical-validation gate**: The Phase B trivial-pass test (`assertions.sh = exit 0`) is the gate that verifies multi-envelope upfront semantics actually work as designed. If the runtime turns out to ignore envelopes after the first or close stdin prematurely, the implementer files BLOCKER-002 at that point and we revisit (likely Option B — one-shot only, drop scripted answers from v1).

### D7 — Subprocess model *(resolves PRD OQ7)*

**Decision**: One `claude` subprocess per test for v1. No pooling.

**Rationale**: Pooling introduces shared-state risk (between-test leakage of session memory, MCP auth state, tool-call side effects) for a speed win that's only material at O(100+) tests per run. At O(10-50) tests, per-test startup is acceptable. Pooling is a follow-on PRD when total runtime becomes painful.

## Substrate Abstraction (v1-single-substrate, generalization-ready)

The PRD's "generalization-ready but v1-single-substrate" requirement resolves to an internal dispatch function with a single case:

```
dispatch-substrate <substrate-type> <scratch-dir> <test-dir>
  case "$substrate-type" in
    plugin-skill) exec plugin-kiln/scripts/harness/substrate-plugin-skill.sh "$@" ;;
    *) echo "Substrate '$substrate-type' not implemented in v1" >&2; exit 2 ;;
  esac
```

All substrate-agnostic logic (scratch-dir creation, fixture seeding, TAP emission, watcher spawning, verdict aggregation) lives in the core harness scripts. Substrate-specific logic (how to spawn the session, how to send scripted input, how to detect exit) lives in `substrate-<name>.sh`. To add a future substrate, drop in a new script and add a case. **No refactor of core harness scripts is required.** This is the entire extension point.

The `contracts/interfaces.md` fixes the substrate-script calling convention so that future PRDs match it.

## Project Structure

### Documentation (this feature)

```text
specs/plugin-skill-test-harness/
├── plan.md                       # This file
├── spec.md
├── tasks.md                      # Phase 2 output
├── contracts/
│   └── interfaces.md             # Phase 1 output — YAML schema, TAP grammar, verdict JSON, script sigs
├── agent-notes/
│   └── specifier.md              # Friction notes (FR-009 of build-prd)
└── SMOKE.md                      # Executable meta-fixtures — invoke harness against seed tests
```

### Source Code (repository root)

```text
plugin-kiln/
├── skills/
│   └── kiln-test/
│       └── SKILL.md              # User-facing skill body; portable ${WORKFLOW_PLUGIN_DIR} paths
├── agents/
│   └── test-watcher.md           # Haiku-model classifier agent (D5)
├── scripts/
│   └── harness/
│       ├── kiln-test.sh          # Top-level orchestrator — discovery, loop, TAP header/footer
│       ├── fixture-seeder.sh     # Copies fixtures/ into scratch dir
│       ├── scratch-create.sh     # mkdir /tmp/kiln-test-<uuid>, UUID collision retry
│       ├── claude-invoke.sh      # Wraps `claude --plugin-dir ... --headless ...` (isolates flag drift)
│       ├── substrate-plugin-skill.sh  # Substrate driver for plugin-skill type
│       ├── dispatch-substrate.sh # Internal dispatch (v1: single-case switch)
│       ├── watcher-runner.sh     # Wraps Task call to the test-watcher agent; writes verdict JSON
│       ├── watcher-poll.sh       # Internal: samples subprocess + scratch dir state per poll tick
│       ├── tap-emit.sh           # Emits one TAP line (ok/not ok) + YAML diagnostic
│       ├── scratch-snapshot.sh   # find + sha256sum; writes .kiln/logs/kiln-test-<uuid>-scratch.txt
│       ├── test-yaml-validate.sh # Validates a test.yaml against the schema in contracts/
│       └── config-load.sh        # Loads .kiln/test.config with defaults (stall_window, poll_interval, etc.)
└── tests/
    ├── kiln-distill-basic/
    │   ├── test.yaml
    │   ├── fixtures/             # Seeded scratch state (backlog items for distill to bundle)
    │   ├── inputs/
    │   │   ├── initial-message.txt   # "/kiln:kiln-distill"
    │   │   └── answers.txt           # Scripted answers to prompts (e.g., theme choice)
    │   └── assertions.sh         # Greps generated PRD for expected frontmatter + body
    └── kiln-hygiene-backfill-idempotent/
        ├── test.yaml
        ├── fixtures/             # Seeded specs/ dir with PRDs missing derived_from frontmatter
        ├── inputs/
        │   ├── initial-message.txt   # Script that runs backfill twice
        │   └── answers.txt
        └── assertions.sh         # Greps second run's log for `diff --git`; fails if any appear

CLAUDE.md                          # Update "Available Commands" section with /kiln:kiln-test entry
```

**Structure Decision**: Everything lives in `plugin-kiln/`. No changes to `scaffold/`, `bin/`, or `templates/`. The harness is a plugin-internal tool; consumer projects get it automatically when they update their kiln plugin version.

## Phase Breakdown

- **Phase A** — Skeleton + test.yaml schema + scratch-dir lifecycle + TAP emitter (FR-001, FR-002, FR-003, FR-004, FR-005).
- **Phase B** — plugin-skill substrate driver, including `claude-invoke.sh` wrapper and `KILN_HARNESS=1` env + scratch snapshot (FR-009, FR-010, FR-011, FR-012).
- **Phase C** — Watcher agent spec + runner + verdict reporter (FR-006, FR-007, FR-008).
- **Phase D** — `/kiln:kiln-test` SKILL.md body, wiring all three invocation forms (FR-001).
- **Phase E** — Consumer contract, auto-detection, `.kiln/test.config` loader (FR-013, FR-014).
- **Phase F** — Two seed tests (FR-015).
- **Phase G** — CLAUDE.md "Available Commands" entry for `/kiln:kiln-test`.
- **Phase H** — `SMOKE.md` executable meta-fixtures that invoke the harness against the seed tests and verify exit codes. (Meta-test: the test harness's own test harness.)

Tasks.md expands these into 15-18 concrete items.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Bash-only harness (no compiled-language coverage report) | The harness composes existing `claude` CLI with file-copy primitives and the watcher agent. A compiled implementation would add a language runtime for no behavioral win. Constitutional Article II's 80% coverage gate was written for compiled-language application code. | Writing this in Node.js or Python would require adding a runtime dependency in the plugin for every consumer (NFR-002 forbids); shell is the natural substrate. |
| One-per-test subprocess (no pooling) | Per D7 above — shared-state risk isn't worth the speed win at v1 scale. | Pooling is a follow-on PRD. |
| Substrate dispatch as a single-case switch | V1 ships one substrate; the abstraction is the extension point, not the complexity. | Not abstracting would force a refactor when the second substrate ships. Over-abstracting (plugin manifest, dynamic loading) would exceed v1's needs. |
