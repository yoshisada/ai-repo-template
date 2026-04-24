# Feature PRD: Plugin Skill Test Harness

**Date**: 2026-04-24
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (placeholder; product context inherited from `CLAUDE.md`)

## Background

Every `/kiln:kiln-build-prd` retrospective for the last four consecutive pipelines has flagged the same structural gap: kiln has no way to execute its own skills against a fixture and verify they did what they claimed. `SMOKE.md` files exist in every recent `specs/<feature>/` directory as **documentary fixtures** — markdown tables describing what the skill would produce if it were run — but nothing ever runs them. The implementer of the most recent pipeline (PR #148) wrote in their friction note: "SC-007 load-bearing invariants verified in isolation (helper + regex replay); a live end-to-end `/kiln:kiln-build-prd` run against a consumer repo was not performed from this sandbox. Recommended retro follow-on: smoke-test harness that shells out to the actual skills in a `/tmp` scratch dir." The same recommendation appears in retros #142, #145, and #147. It is now the single highest-severity unaddressed architectural gap.

This PRD closes that gap for the plugin-skill substrate — the immediate bottleneck. The broader pattern (web-app QA, CLI/API/mobile testing, the existing `/kiln:kiln-qa-pass` 4-agent team) will eventually migrate to a unified harness architecture, but those substrates are explicitly **not** in this PRD's scope; they will be built as needed via follow-on PRDs. This one delivers the core harness runtime (fixture seeder + driver dispatcher + watcher agent + TAP reporter) plus the plugin-skill substrate driver, which is what unblocks the accumulated retrospective signal.

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|-------------|--------|------|--------------|------------------|
| 1 | [Executable skill-test harness — invoke skills against /tmp scratch, stop simulating output](../../../.kiln/feedback/2026-04-24-kiln-needs-an-executable-skill-test-harness.md) | `.kiln/feedback/` | feedback | — | high / architecture |

## Problem Statement

**Strategic problem (feedback).** Every pipeline ships SMOKE.md fixtures that describe what the skill *would* do, but no mechanism exists to actually run the skill against the fixture and confirm the output matches. This turns SMOKE.md into documentation that ages into lies — the fixture may have been correct when written, but six skill-body edits later, no one has verified whether it still matches. The accumulating drift is invisible until a real regression ships to main, at which point the hygiene audit or a broken pipeline catches it retroactively. The propose-don't-apply family of skills (claude-audit, hygiene, hygiene-backfill) are especially exposed: their output shape is grep-anchored, and the SMOKE fixtures are the only definition of correctness.

**Tactical evidence.** PR #146's fix for `/kiln:kiln-build-prd` Step 4b was motivated by the hygiene audit catching four post-merge leaks — the hygiene audit is doing its job as a safety net for Step 4b, but the retro noted that "if Step 4b had reported `scanned X items, matched Y, flipped Z` from day one, the feedback-side miss would have been obvious the first time it happened." A harness would have caught that miss before PR #141 ever merged. Similarly, PR #148's migration tool (hygiene-backfill subcommand) has no executable test; its idempotence property (FR-010) is verified only by a manual two-run check in the friction note. Every future edit to that tool risks silently breaking idempotence.

This is architectural: the test infrastructure itself does not exist. Adding one more `SMOKE.md` does not fix the problem; the problem is that no mechanism reads `SMOKE.md` and runs the skill against it.

## Goals

- **Executable tests replace documentary SMOKE.md as the default.** Every skill under `plugin-kiln/skills/` that the maintainer considers load-bearing gets at least one executable test that invokes the real skill via a native-runtime substrate against a scratch-dir fixture, then runs assertions on the final state.
- **Native-runtime execution.** The test harness does not simulate or inline the skill body. It spawns a real `claude --plugin-dir ./plugin-kiln --headless` subprocess per test so the skill runs inside its actual runtime, against its actual dispatcher, with the actual plugin resolution rules.
- **Watcher agent replaces hard timeouts.** A long-running skill invocation is not auto-killed after N minutes or M turns. A watcher agent classifies the session state (healthy / paused for input / stalled / failed) by tailing the session's transcript log and monitoring scratch-dir file-write heartbeats, then decides whether to continue, supply a scripted answer, or report and terminate.
- **One skill, not many.** The harness is a single `/kiln:kiln-test` entry point plus one consumer contract (fixture directory format). Individual tests are fixture directories, not skills.
- **Generalization-ready architecture, plugin-skill substrate only v1.** The harness is internally structured around a `substrate` abstraction so that web-app / CLI-app / API / mobile substrates can be added as follow-on PRDs without restructuring v1. But v1 SHIPS ONLY the `plugin-skill` substrate. No Playwright integration, no CLI-binary driver, no API driver, no Maestro integration in this PRD.

## Non-Goals

- **Web-app substrate.** No Playwright driver, no browser fixture seeding, no DOM assertion helpers. Follow-on PRD — user will build when needed.
- **CLI-app substrate.** No native-binary spawn/pipe driver. Follow-on PRD.
- **API substrate.** No HTTP request fixture format, no server spawn driver. Follow-on PRD.
- **Mobile substrate.** No Maestro integration. Follow-on PRD.
- **Refactor of `/kiln:kiln-qa-pass` / `/kiln:kiln-qa-pipeline` / `smoke-tester` agent.** These exist and work today; they can migrate to the unified harness in a later PRD once the web-app substrate ships. This PRD leaves them untouched.
- **Auto-generation of tests from SMOKE.md.** A migration tool that parses existing `specs/<feature>/SMOKE.md` and emits a fixture directory is a reasonable follow-on, but it is not in scope here. Maintainers write the first batch of tests manually.
- **Test coverage requirements or gates.** This PRD ships the mechanism, not a policy. No hook enforces "every skill must have a test." That's a separate maintainership decision for a later PRD.
- **Interactive dev-loop ergonomics beyond running a test once.** No file-watch / auto-rerun loop. The harness runs once per invocation; `watch -n 10 kiln:kiln-test ...` is the user's shell, not a feature.
- **Cross-plugin test runs in a single invocation.** V1 runs one plugin's tests per invocation. If you want to test both `plugin-kiln` and `plugin-shelf`, you run the harness twice.

## Requirements

### Functional Requirements

**Core harness (substrate-agnostic):**

- **FR-001 (from `.kiln/feedback/2026-04-24-kiln-needs-an-executable-skill-test-harness.md`)**: A new skill `/kiln:kiln-test` MUST be shipped under `plugin-kiln/skills/kiln-test/`. Invocations:
  - `/kiln:kiln-test` — auto-detects the plugin in the current working directory (looks for `plugin-<name>/` as a sibling of `CWD`) and runs all tests for that plugin
  - `/kiln:kiln-test <plugin-name>` — runs all tests for the named plugin
  - `/kiln:kiln-test <plugin-name> <test-name>` — runs one specific test
- **FR-002**: Each test is a directory at a canonical discovery path (plan-phase decision OQ1; default recommendation: `plugin-<name>/tests/<test-name>/`). The directory MUST contain:
  - `test.yaml` — test metadata (substrate type, skill under test, expected exit, description)
  - `fixtures/` — initial scratch-dir state (copied wholesale into the scratch dir before invocation)
  - `inputs/` — substrate-specific input files (see substrate-specific FRs below)
  - `assertions.sh` — executable script run against the final scratch-dir state; non-zero exit = failure
- **FR-003**: The harness MUST create an isolated scratch dir for each test under `/tmp/kiln-test-<uuid>/`. All test invocations run inside that scratch dir. The scratch dir is deleted on success; retained on failure with the UUID path logged for diagnosis.
- **FR-004**: The harness MUST emit TAP-compatible output (one `ok N - <test-name>` or `not ok N - <test-name>` line per test, with a diagnostic block following each `not ok` line). Exact shape is plan-phase decision OQ4; default: TAP version 14 with YAML diagnostic blocks.
- **FR-005**: Per-test exit code MUST be: 0 = pass, 1 = fail (assertion failed or watcher terminated), 2 = inconclusive (test metadata malformed, fixture missing, substrate unavailable). The overall harness exit code MUST be 0 iff every test passed.

**Watcher agent:**

- **FR-006**: A watcher agent (spec at `plugin-kiln/agents/test-watcher.md`, model: haiku for cost) MUST run alongside each test invocation. It classifies the session state at regular intervals (plan-phase decision OQ3; default: every 30 seconds):
  - **healthy** — session is writing to the scratch dir AND transcript is advancing. Leave alone.
  - **paused for input** — session emitted a prompt pattern (e.g., `?` followed by a blank line, or literal "Waiting for input") and is idle. Trigger scripted-answer lookup (see FR-009).
  - **stalled** — no transcript advance AND no scratch-dir writes for the stall window (plan-phase decision; default: 5 minutes). Report and terminate the session.
  - **failed** — transcript contains an unrecoverable error pattern (plan-phase decision OQ3; default: non-zero exit from the subprocess). Report and terminate.
- **FR-007**: The watcher MUST write a verdict report to `.kiln/logs/kiln-test-<uuid>.md` containing: final classification, stall/pause timestamps, last 50 transcript lines, list of files written to scratch dir, scratch dir UUID (for diagnosis if retained).
- **FR-008**: The watcher MUST NOT use hard duration or turn-count caps. No `--max-turns N`, no `timeout M`, no session-level auto-kill. Classification drives termination, not the clock.

**Plugin-skill substrate:**

- **FR-009**: The `plugin-skill` substrate driver MUST spawn a fresh `claude --plugin-dir <plugin-root> --headless --dangerously-skip-permissions --initial-message "$(cat inputs/initial-message.txt)"` subprocess per test, with the scratch dir as the CWD. The `--plugin-dir` path points at the source tree of the plugin under test (e.g., `./plugin-kiln`), so skill dispatch resolves against local source, not the marketplace cache.
- **FR-010**: When the watcher detects a "paused for input" state, the driver MUST read the next answer from `inputs/answers.txt` (one line per expected prompt, consumed in order) and send it to the headless session's stdin. If `answers.txt` is exhausted or missing, the test fails with a diagnostic naming the unanswered prompt.
- **FR-011**: The driver MUST set an env var `KILN_HARNESS=1` before spawning. Skills under test MAY check this env var to skip interactive features that require a real human (e.g., a skill that normally asks `gh auth login` might skip that check when `KILN_HARNESS=1`). This is a discipline, not a requirement — most skills work unmodified.
- **FR-012**: After the session exits, the driver MUST snapshot the scratch dir's final state (`find . -type f` + SHA-256 of each) into `.kiln/logs/kiln-test-<uuid>-scratch.txt` for diagnosis.

**Consumer contract (tests ship in the plugin):**

- **FR-013**: Every plugin repo MAY ship tests under the canonical discovery path (FR-002). `/kiln:kiln-test` MUST be able to run them end-to-end against the local source tree with no additional setup beyond `claude` being on PATH and the plugin's own dependencies being installed.
- **FR-014**: The harness MUST be invokable from any directory that contains a `plugin-<name>/` dir (source-repo layout) without additional config. A `.kiln/test.config` file MAY override defaults (discovery path, watcher thresholds, substrate-specific options) but is optional; defaults MUST be sensible for a clean source-repo checkout.
- **FR-015**: A minimum of **two seed tests** MUST ship in this PRD's delivery: one test of `/kiln:kiln-distill` (a simple leaf skill) and one test of `/kiln:kiln-hygiene --backfill` (the subcommand shipped in PR #148, exercising idempotence). These seed tests serve as executable documentation of the test format and demonstrate the harness on a non-trivial fixture.

### Non-Functional Requirements

- **NFR-001**: Plugin portability. The `/kiln:kiln-test` skill body and any supporting scripts MUST be resolvable via `${WORKFLOW_PLUGIN_DIR}/...` when invoked from inside a consumer repo (per CLAUDE.md plugin workflow portability rule). No repo-relative `plugin-kiln/scripts/...` paths in the SKILL.md body.
- **NFR-002**: No new MCP dependencies. The harness uses standard shell + `claude` + existing Claude Code tooling. No Obsidian writes, no `gh` calls (beyond what the skill under test might do itself).
- **NFR-003**: Determinism. The harness's own output for an identical test + fixture + skill-source must be byte-identical across runs (modulo timestamps and UUIDs — which appear only in the verdict report, not in TAP output). The TAP file is diffable.
- **NFR-004**: Isolation. Each test's scratch dir is fully isolated; tests MUST NOT be able to write to the plugin source tree, the user's home dir, or any path outside the scratch dir. Enforced by the scratch-dir CWD + watcher-observed scratch-dir-write-only invariant.
- **NFR-005**: Backwards compatibility. Existing `specs/<feature>/SMOKE.md` files are untouched by this PRD. The harness does not read them, migrate them, or deprecate them. They remain as documentary artifacts until a follow-on PRD replaces them with executable tests one by one.
- **NFR-006**: Cost awareness. Each test spawns a fresh `claude` subprocess — not cheap. Ballpark 5-10 seconds of startup per test on top of the skill's actual work. The harness SHOULD support running a named subset of tests (FR-001 third form), and CI runs SHOULD be opt-in (not on every commit). Cost budget is a maintainership decision, not a mechanism requirement.

## User Stories

**Story 1 — Plugin author runs a test after editing a skill.**
As a maintainer who just edited `plugin-kiln/skills/kiln-distill/SKILL.md`, I want to run `/kiln:kiln-test kiln kiln-distill` and get back `ok 1 - kiln-distill-basic` (or a specific failure diagnostic) within two minutes. Acceptance: the test harness spawns a `claude --plugin-dir ./plugin-kiln --headless` subprocess against a `/tmp/kiln-test-<uuid>/` scratch dir seeded with a fixture backlog, invokes `/kiln:kiln-distill`, supplies the scripted "which theme?" answer from `answers.txt`, and runs `assertions.sh` which greps the generated PRD for expected frontmatter + body table.

**Story 2 — Plugin author catches an idempotence regression.**
As a maintainer about to merge a change to the `/kiln:kiln-hygiene --backfill` migration tool, I want a regression test that fails loudly if a second backfill run emits any diff hunks. Acceptance: a seed test with two invocations of the backfill subcommand; the second invocation's output is `.kiln/logs/prd-derived-from-backfill-<ts2>.md`; `assertions.sh` fails if that file contains any `diff --git` line.

**Story 3 — Watcher catches a stalled test without hard-killing a long pipeline.**
As a maintainer running a test against `/kiln:kiln-build-prd` that legitimately takes 20+ minutes, I want the watcher to NOT kill the session at 5 or 20 minutes, but to KILL it if the session stops writing files and stops advancing the transcript for 5 consecutive minutes. Acceptance: a stalled-session test fixture that artificially hangs a skill; the watcher reports `stalled` at ~5-minute mark with a diagnostic; exit code 1; retained scratch dir for diagnosis.

## Success Criteria

- **SC-001**: `/kiln:kiln-test kiln kiln-distill` runs a real `/kiln:kiln-distill` invocation end-to-end against a fixture backlog and emits a TAP line `ok 1 - kiln-distill-basic`. Verified by running the harness against the seed test shipped per FR-015.
- **SC-002**: `/kiln:kiln-test kiln kiln-hygiene-backfill` runs two back-to-back backfill invocations and asserts the second one's log contains zero diff hunks. Verified by running the seed test.
- **SC-003**: A deliberately-broken skill change (e.g., remove a line from the distill body that writes the frontmatter) causes `/kiln:kiln-test kiln kiln-distill` to emit `not ok 1 - kiln-distill-basic` with a diagnostic pointing at the missing frontmatter. Verified by temporarily breaking distill in a verification branch and confirming the harness reports the break.
- **SC-004**: The watcher correctly classifies a stalled session (artificially hung skill) and terminates with a diagnostic report within `stall_window + 30s`. Verified by a stalled-session fixture in the seed tests.
- **SC-005**: The watcher does NOT terminate a long-running but healthy session. Verified by running the harness against a `/kiln:kiln-build-prd`-shaped fixture that takes >10 minutes and confirming it completes without a `stalled` verdict.
- **SC-006**: Fresh local edits to `plugin-kiln/skills/<skill>/SKILL.md` are picked up by the very next harness invocation with no `/plugin reload` and no cache flush. Verified by editing a seed skill in-place and confirming the test behavior changes on re-run.
- **SC-007**: Scratch dir isolation — the harness MUST NOT write outside `/tmp/kiln-test-<uuid>/` and the skill under test MUST NOT be able to modify the plugin source tree. Verified by a test that deliberately attempts to write to `plugin-kiln/skills/kiln-distill/SKILL.md` during execution and asserts the write was either blocked or contained to the scratch dir's shadow copy.
- **SC-008**: TAP output determinism — running the same test twice against unchanged source produces byte-identical TAP output (modulo scratch-dir UUIDs, which are confined to the verdict report, not the TAP stream). Verified by a diff check in CI or in the harness's own meta-test.
- **SC-009**: The harness emits exit code 0 when all tests pass and 1 when any test fails. Verified by running against a known-passing seed test set and against a known-failing set.
- **SC-010**: Seed tests ship as `plugin-kiln/tests/kiln-distill-basic/` and `plugin-kiln/tests/kiln-hygiene-backfill-idempotent/` (or per-plan-phase-decided discovery path) and are invokable via `/kiln:kiln-test kiln` out of the box.

## Tech Stack

Inherited from `CLAUDE.md`:
- Node.js 18+ (init.mjs)
- Bash 5.x (hooks, workflows, harness scripts)
- Markdown + YAML (skills/agents/test metadata)
- `jq` (YAML/JSON parsing in shell)

**Additions for this feature**:
- `claude` CLI on PATH (all consumers already have this; it's the entry point for Claude Code)
- POSIX `find` + `sha256sum` (for scratch-dir state snapshot) — all systems
- **No new runtime dependencies.** The harness is bash + markdown + one agent spec.

**Explicitly out-of-stack for v1** (follow-on PRDs may add):
- Playwright (web-app substrate)
- Maestro (mobile substrate)
- `curl` / HTTP fixture runners (API substrate)

## Risks & Open Questions

- **Risk 1 — Subprocess startup cost dominates.** Each test takes ~5-10s of `claude --headless` startup. With 20 seed tests, a full run is 2-4 minutes. Mitigation: the harness supports running a single named test (FR-001 third form) so fast dev iteration stays fast. CI runs the full suite opt-in (not on every commit). Long-term optimization (connection pooling, test batching in one process) is a follow-on, not a v1 concern.
- **Risk 2 — `--dangerously-skip-permissions` blast radius.** The harness uses this flag so tool-use prompts don't block the headless session. An malicious skill-under-test could in principle do destructive things to the scratch dir. Mitigation: scratch dir is `/tmp/kiln-test-<uuid>/`, fully isolated; skill can't write outside it (NFR-004); the source tree is read-only during the run (the `--plugin-dir` mount is effectively read-only from the skill's perspective since the CWD is the scratch dir, not the plugin source). If the test SUITE is untrusted (e.g., running someone else's plugin's tests), the user should read the assertions + fixtures before running — same discipline as running any shell script from an external repo.
- **Risk 3 — Watcher classification false positives.** A skill that legitimately does a long-running shell command (e.g., `npm install`, `git clone`) might produce no transcript advance and no scratch-dir writes for several minutes, triggering a `stalled` verdict incorrectly. Mitigation: `npm install` / `git clone` / other known-slow substrates can be handled by having the skill emit a heartbeat file (`echo "still working" >> .kiln-heartbeat` every 10s); the watcher treats heartbeat-file writes as scratch-dir activity. This is a discipline, but the watcher's classifier already monitors all scratch-dir writes, so implementing it is trivial.
- **Risk 4 — Claude Code CLI flag drift.** `--plugin-dir`, `--headless`, and `--dangerously-skip-permissions` are the current flag names; they could be renamed or removed in a future Claude Code release. Mitigation: wrap all flag invocations in a single helper script (`plugin-kiln/scripts/harness/claude-invoke.sh`), so a future flag rename is a one-file change. Document the CLI contract in a comment at the top of that script.
- **Open question OQ1**: Canonical discovery path for tests. Candidates: `plugin-<name>/tests/` (co-located with skill source), `.kiln/harness/tests/` (kiln-centric), `tests/plugin-<name>/` (repo-root). Recommendation: `plugin-<name>/tests/` — keeps tests next to the source they test, matches pytest/jest conventions, does not conflate with `.kiln/` which is for runtime state.
- **Open question OQ2**: Answer-file format for scripted input. Candidates: `answers.txt` (one line per prompt), `answers.yaml` (prompt-regex → answer map), `answers.jsonl` (structured). Recommendation: `answers.txt` for v1 (simplest); a future enhancement could match by prompt regex if we find that fragile.
- **Open question OQ3**: Watcher classification thresholds. Candidates: stall window 5m / 10m / 15m; poll interval 15s / 30s / 60s. Recommendation: stall 5m, poll 30s. These are overridable via `.kiln/test.config`.
- **Open question OQ4**: TAP output version + diagnostic shape. Candidates: TAP v13 (widely supported), TAP v14 (adds YAML diagnostics), JSON-lines (non-TAP). Recommendation: TAP v14 with YAML diagnostic blocks — supported by most TAP consumers (tape, prove, tap-* packages) and human-readable.
- **Open question OQ5**: Where the watcher agent lives. Candidates: `plugin-kiln/agents/test-watcher.md` (co-located with other kiln agents), `plugin-kiln/skills/kiln-test/agents/test-watcher.md` (nested inside the skill). Recommendation: `plugin-kiln/agents/test-watcher.md` — matches the shape of existing kiln agents (qa-engineer, debugger, smoke-tester).
- **Open question OQ6**: `--dangerously-skip-permissions` vs. a safer alternative. Candidates: use the dangerous flag as planned, use `--auto-approve-tools <list>` (if such a flag exists), run the harness in a sandbox (Docker / firejail). Recommendation: `--dangerously-skip-permissions` for v1, scratch-dir isolation as the safety boundary. Sandbox is a follow-on.
- **Open question OQ7**: Connection pooling / test batching. Whether to spawn one claude subprocess per test (simple, slow) or one long-lived subprocess that runs tests sequentially (faster, more complex, shared-state risk). Recommendation: one per test for v1 (isolation > speed); revisit if/when we have enough tests that total runtime becomes painful.
