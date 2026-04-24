# Feature Specification: Plugin Skill Test Harness

**Feature Branch**: `build/plugin-skill-test-harness-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Input**: User description: "Ship an executable skill-test harness that invokes real `claude --plugin-dir ./plugin-kiln --headless` subprocesses against `/tmp/kiln-test-<uuid>/` scratch-dir fixtures, watched by a classifier agent that replaces hard timeouts. V1 delivers the core harness (fixture seeder + driver dispatcher + watcher + TAP reporter) plus the `plugin-skill` substrate driver only. Web/CLI/API/mobile substrates are out of scope — they will ship as follow-on PRDs when needed."
**Parent PRD**: [docs/features/2026-04-24-plugin-skill-test-harness/PRD.md](../../docs/features/2026-04-24-plugin-skill-test-harness/PRD.md)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plugin author runs a test after editing a skill (Priority: P1)

As a maintainer who just edited a skill under `plugin-kiln/skills/<skill>/SKILL.md`, I want to run `/kiln:kiln-test kiln <skill>` and get back a TAP `ok` line (or a specific failure diagnostic) without manual setup. The harness must spawn a real `claude --plugin-dir ./plugin-kiln --headless` subprocess against a scratch-dir fixture, invoke the skill, supply any scripted prompt answers, and run the test's assertions.

**Why this priority**: This is the primary motivating use case. Without it, `SMOKE.md` fixtures remain documentary and age into lies. Everything else in the feature exists to make this work.

**Independent Test**: Editing `plugin-kiln/skills/kiln-distill/SKILL.md` and running `/kiln:kiln-test kiln kiln-distill` produces `ok 1 - kiln-distill-basic` against the FR-015 seed test; breaking the skill produces `not ok 1 - kiln-distill-basic` with a diagnostic pointing at the regression.

**Acceptance Scenarios**:

1. **Given** a clean `plugin-kiln/` source tree with the `kiln-distill-basic` seed test installed and `/kiln:kiln-distill` working correctly, **When** the maintainer runs `/kiln:kiln-test kiln kiln-distill`, **Then** the harness creates `/tmp/kiln-test-<uuid>/`, seeds fixtures, spawns `claude --plugin-dir ./plugin-kiln --headless` with the initial message from `inputs/initial-message.txt`, runs `assertions.sh` on the final scratch-dir state, emits `ok 1 - kiln-distill-basic` on stdout, exits 0, and deletes the scratch dir.
2. **Given** a maintainer has just edited `plugin-kiln/skills/kiln-distill/SKILL.md` and removed the frontmatter-writing step, **When** they run `/kiln:kiln-test kiln kiln-distill`, **Then** the harness emits `not ok 1 - kiln-distill-basic` with a YAML diagnostic block naming the missing frontmatter, exits 1, and retains the scratch dir with its UUID path logged for diagnosis.
3. **Given** no arguments and a CWD containing `plugin-kiln/`, **When** the maintainer runs `/kiln:kiln-test`, **Then** the harness auto-detects `plugin-kiln` as the plugin under test and runs every test under its canonical discovery path.

---

### User Story 2 - Plugin author catches an idempotence regression (Priority: P2)

As a maintainer about to merge a change to the `/kiln:kiln-hygiene --backfill` migration tool, I want a regression test that fails loudly if a second backfill run emits any diff hunks. The test runs the backfill subcommand twice back-to-back and asserts the second invocation's log contains no `diff --git` lines.

**Why this priority**: Idempotence properties are the hardest to verify manually and the easiest to regress silently. PR #148 shipped this subcommand with only a manual two-run check in the friction note; every subsequent edit is an unverified bet.

**Independent Test**: The `kiln-hygiene-backfill-idempotent` seed test ships alongside the harness and demonstrates the pattern. Running it against the shipped backfill tool must produce `ok`; breaking idempotence (by making the backfill emit diff hunks on the second run) must produce `not ok` with a diagnostic naming the unexpected diff lines.

**Acceptance Scenarios**:

1. **Given** the `kiln-hygiene-backfill-idempotent` seed test and a working backfill tool, **When** `/kiln:kiln-test kiln kiln-hygiene-backfill-idempotent` runs, **Then** the harness invokes the backfill twice against the same fixture, runs `assertions.sh` which greps the second log for `diff --git`, and emits `ok` when no diff lines appear.
2. **Given** a regression has been introduced that causes the second backfill run to emit diff hunks, **When** the same test runs, **Then** the harness emits `not ok` with a diagnostic quoting the unexpected diff lines and exits 1.

---

### User Story 3 - Watcher catches a stalled test without hard-killing a long pipeline (Priority: P2)

As a maintainer running a test against `/kiln:kiln-build-prd` that legitimately takes 20+ minutes, I want the watcher to NOT kill the session at 5 or 20 minutes, but to KILL it only if the session stops writing files and stops advancing the transcript for 5 consecutive minutes.

**Why this priority**: Classification-driven termination is the architectural differentiator from existing harnesses. Without it, either legitimate long-running pipelines get killed or stalled tests hang forever.

**Independent Test**: A stalled-session fixture that artificially hangs a skill must cause the watcher to classify `stalled` within `stall_window + 30s` and terminate; a separately-runnable healthy long-running fixture (>10 min) must complete without a `stalled` verdict.

**Acceptance Scenarios**:

1. **Given** a stalled-session fixture that hangs without writing files or advancing the transcript, **When** the harness runs it, **Then** the watcher classifies `stalled` no sooner than `stall_window` (default 5m) and no later than `stall_window + poll_interval` (default 5m 30s), writes a verdict report to `.kiln/logs/kiln-test-<uuid>.md`, terminates the subprocess, and emits `not ok` with exit code 1.
2. **Given** a healthy long-running session that writes heartbeat files every 10 seconds for 12 minutes, **When** the harness runs it, **Then** the watcher never classifies `stalled`, the session runs to completion, and the test exits on the session's own terms (pass or fail from assertions, not termination).
3. **Given** a session that emits a prompt pattern (e.g., "Waiting for input") and goes idle, **When** the watcher classifies `paused for input`, **Then** the driver reads the next line from `inputs/answers.txt` and writes it to the subprocess's stdin; if `answers.txt` is missing or exhausted, the test fails with a diagnostic naming the unanswered prompt.

---

### Edge Cases

- **Malformed `test.yaml`**: If a test directory's `test.yaml` is missing required keys or has invalid types, the harness MUST exit that test with code 2 (inconclusive) and emit a TAP diagnostic naming the schema violation; other tests in the suite continue.
- **Missing `fixtures/` or `assertions.sh`**: Treated as inconclusive (exit 2), not a failure.
- **Scratch dir already exists**: UUID collision is astronomically unlikely, but if `/tmp/kiln-test-<uuid>/` already exists at creation time, the harness MUST generate a new UUID and retry, up to 3 attempts, then fail inconclusive.
- **`answers.txt` contains more lines than the session prompts for**: Unused lines are silently discarded at session exit; the test is not failed on this basis alone.
- **Skill writes outside scratch dir**: Detected by the scratch-dir-write-only invariant; the watcher MUST flag it in the verdict report. V1 does not guarantee a hard block of out-of-scratch writes (no sandbox); it guarantees detection.
- **`claude` not on PATH**: The harness MUST exit 2 (inconclusive) with a diagnostic naming the missing binary before attempting any test invocation.
- **Multiple plugins in CWD**: If `/kiln:kiln-test` is invoked with no arguments and more than one `plugin-<name>/` sibling exists, the harness MUST exit 2 with a diagnostic listing the candidate plugins and instructing the user to pass an explicit plugin name.
- **Watcher poll races subprocess exit**: If the subprocess exits between watcher polls, the watcher MUST detect the exit via the subprocess PID status at the next poll (at most `poll_interval` later) and finalize the verdict.

## Requirements *(mandatory)*

### Functional Requirements

**Core harness (substrate-agnostic):**

- **FR-001**: A new skill `/kiln:kiln-test` MUST be shipped under `plugin-kiln/skills/kiln-test/`. It MUST support three invocation forms: (a) `/kiln:kiln-test` auto-detects the plugin in the current working directory by looking for a `plugin-<name>/` sibling and runs all tests for that plugin; (b) `/kiln:kiln-test <plugin-name>` runs all tests for the named plugin; (c) `/kiln:kiln-test <plugin-name> <test-name>` runs one specific test.
- **FR-002**: Each test MUST be a directory at the canonical discovery path (per plan Decision D1). The directory MUST contain `test.yaml` (test metadata — substrate type, skill under test, expected exit, description), `fixtures/` (initial scratch-dir state, copied wholesale into the scratch dir before invocation), `inputs/` (substrate-specific input files), and `assertions.sh` (executable script run against the final scratch-dir state; non-zero exit = failure).
- **FR-003**: The harness MUST create an isolated scratch dir for each test at `/tmp/kiln-test-<uuid>/` where `<uuid>` is a UUIDv4. All test invocations run with that scratch dir as CWD. The scratch dir MUST be deleted on success and retained on failure; the retained UUID path MUST be written to the verdict report for diagnosis.
- **FR-004**: The harness MUST emit TAP-compatible output on stdout: one `ok N - <test-name>` line per passing test, one `not ok N - <test-name>` line per failing test, with a YAML diagnostic block following each `not ok` line (per plan Decision D4).
- **FR-005**: Per-test exit code MUST be 0 for pass, 1 for fail (assertion failed or watcher terminated), 2 for inconclusive (test metadata malformed, fixture missing, substrate unavailable). The overall harness exit code MUST be 0 if and only if every test passed (no inconclusive tests, no failures).

**Watcher agent:**

- **FR-006**: A watcher agent with its spec at `plugin-kiln/agents/test-watcher.md` (model: haiku for cost; per plan Decision D5) MUST run alongside each test invocation and classify the session state at regular intervals (default poll interval per plan Decision D3). Classifications: `healthy` (session is writing to the scratch dir AND transcript is advancing; leave alone); `paused for input` (session emitted a prompt pattern and is idle; trigger scripted-answer lookup per FR-010); `stalled` (no transcript advance AND no scratch-dir writes for the stall window; report and terminate); `failed` (transcript contains an unrecoverable error pattern or subprocess exited non-zero; report and terminate).
- **FR-007**: The watcher MUST write a verdict report to `.kiln/logs/kiln-test-<uuid>.md` containing: final classification, stall/pause timestamps, last 50 transcript lines, list of files written to the scratch dir, and the scratch dir UUID (for diagnosis if the scratch dir was retained).
- **FR-008**: The watcher MUST NOT apply hard duration or turn-count caps. No `--max-turns`, no `timeout`, no session-level auto-kill. Classification drives termination.

**Plugin-skill substrate:**

- **FR-009**: The `plugin-skill` substrate driver MUST spawn a fresh `claude --plugin-dir <plugin-root> --headless --dangerously-skip-permissions --initial-message "$(cat inputs/initial-message.txt)"` subprocess per test, with the scratch dir as CWD. The `--plugin-dir` path MUST point at the source tree of the plugin under test (e.g., `./plugin-kiln`) so skill dispatch resolves against local source, not the marketplace cache. Per plan Decision D7, v1 uses one subprocess per test — no pooling.
- **FR-010**: When the watcher classifies `paused for input`, the driver MUST read the next line from `inputs/answers.txt` and send it to the headless session's stdin (per plan Decision D2: one answer per line, consumed in FIFO order). If `answers.txt` is exhausted or missing, the test MUST fail with a diagnostic naming the unanswered prompt.
- **FR-011**: The driver MUST set environment variable `KILN_HARNESS=1` before spawning the subprocess. Skills under test MAY check this variable to skip interactive features that require a real human; this is a discipline, not a requirement.
- **FR-012**: After the session exits, the driver MUST snapshot the scratch dir's final state (`find . -type f` plus SHA-256 of each file) into `.kiln/logs/kiln-test-<uuid>-scratch.txt` for diagnosis.

**Consumer contract (tests ship in the plugin):**

- **FR-013**: Every plugin repo MAY ship tests under the canonical discovery path (FR-002, per plan Decision D1). `/kiln:kiln-test` MUST be able to run them end-to-end against the local source tree with no additional setup beyond `claude` being on PATH and the plugin's own dependencies being installed.
- **FR-014**: The harness MUST be invokable from any directory that contains a `plugin-<name>/` directory (source-repo layout) without additional config. A `.kiln/test.config` file MAY override defaults (discovery path, watcher stall window, watcher poll interval, substrate-specific options) but MUST be optional; defaults MUST produce a successful run on a clean source-repo checkout of `plugin-kiln`.
- **FR-015**: Two seed tests MUST ship in this PRD's delivery: (a) `kiln-distill-basic` — a simple-leaf-skill test that runs `/kiln:kiln-distill` against a fixture backlog; (b) `kiln-hygiene-backfill-idempotent` — a two-invocation regression test that asserts the second backfill run emits no diff hunks. These seed tests serve as executable documentation of the test format and demonstrate the harness on non-trivial fixtures.

### Non-Functional Requirements

- **NFR-001** (Plugin portability): The `/kiln:kiln-test` SKILL.md body and all supporting scripts invoked from it MUST be resolvable via `${WORKFLOW_PLUGIN_DIR}/...` when the skill is invoked from inside a consumer repo. No repo-relative `plugin-kiln/scripts/...` path may appear in the SKILL.md body.
- **NFR-002** (No new MCP deps): The harness MUST use standard shell plus the `claude` CLI plus existing Claude Code tooling. No Obsidian writes, no `gh` calls (beyond what a skill under test might do itself), no new runtime packages.
- **NFR-003** (Determinism): The harness's own output for an identical test + fixture + skill-source MUST be byte-identical across runs, modulo timestamps and UUIDs. UUIDs MUST appear only in the verdict report and scratch-dir snapshot path — never in the TAP stream on stdout.
- **NFR-004** (Isolation): Each test's scratch dir MUST be fully isolated at `/tmp/kiln-test-<uuid>/`. The harness MUST detect (but is not required to hard-block) writes outside that directory via the watcher's scratch-dir-write-only invariant. The plugin source tree MUST be treated as read-only by the skill under test (the CWD is the scratch dir, the `--plugin-dir` mount is referenced for resolution only).
- **NFR-005** (Backwards compatibility): Existing `specs/<feature>/SMOKE.md` files MUST NOT be read, migrated, or deprecated by this feature. They remain documentary artifacts.
- **NFR-006** (Cost awareness): Each test spawns a fresh `claude` subprocess with ~5-10 seconds of startup overhead. The harness MUST support running a single named test (FR-001 third form) for fast dev iteration. CI-wide enforcement of "every skill has a test" is NOT in this feature's scope.

### Key Entities

- **Test directory**: A directory at the canonical discovery path (per plan Decision D1). Contents: `test.yaml` (metadata), `fixtures/` (initial scratch state), `inputs/` (initial-message.txt, answers.txt), `assertions.sh` (final-state assertions).
- **Scratch dir**: `/tmp/kiln-test-<uuid>/` — the isolated CWD for one test invocation. Populated by fixture seeder, written to by the skill under test, snapshotted at exit, deleted on success / retained on failure.
- **Verdict report**: `.kiln/logs/kiln-test-<uuid>.md` — watcher-written classification + evidence (timestamps, last 50 transcript lines, scratch file list, scratch UUID).
- **Scratch snapshot**: `.kiln/logs/kiln-test-<uuid>-scratch.txt` — `find . -type f` plus SHA-256 of each file, captured after session exit.
- **TAP stream**: The harness's stdout — deterministic across identical runs, diffable, UUID-free.
- **Substrate driver**: Pluggable component responsible for spawning the process/session being tested. V1 ships only the `plugin-skill` substrate driver; web/CLI/API/mobile drivers are out of scope (see Out of Scope).
- **Watcher agent**: `plugin-kiln/agents/test-watcher.md` — haiku-model classifier that polls the subprocess + scratch dir and emits one of `healthy`, `paused for input`, `stalled`, `failed`.

## Out of Scope *(v1 non-goals)*

These are explicitly NOT deferred FRs. They are excluded from this feature. Each becomes a follow-on PRD when the need is concrete.

- **Web-app substrate** (Playwright driver, browser fixture seeding, DOM assertion helpers)
- **CLI-app substrate** (native-binary spawn/pipe driver)
- **API substrate** (HTTP request fixture format, server spawn driver)
- **Mobile substrate** (Maestro integration)
- **Refactor of `/kiln:kiln-qa-pass` / `/kiln:kiln-qa-pipeline` / `smoke-tester` agent** — these remain untouched
- **Auto-generation of tests from SMOKE.md** — maintainers write the first batch manually
- **Test coverage gates or hooks** — no "every skill must have a test" enforcement
- **Interactive dev-loop ergonomics** — no file-watch / auto-rerun
- **Cross-plugin test runs in a single invocation** — one plugin's tests per invocation

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `/kiln:kiln-test kiln kiln-distill-basic` runs a real `/kiln:kiln-distill` invocation end-to-end against a fixture backlog and emits a TAP line `ok 1 - kiln-distill-basic`. Verified against the seed test shipped per FR-015.
- **SC-002**: `/kiln:kiln-test kiln kiln-hygiene-backfill-idempotent` runs two back-to-back backfill invocations and asserts the second run's log contains zero `diff --git` lines. Verified against the seed test.
- **SC-003**: A deliberately broken skill change (e.g., removing the frontmatter-writing line from the distill body) causes `/kiln:kiln-test kiln kiln-distill-basic` to emit `not ok 1 - kiln-distill-basic` with a diagnostic pointing at the missing frontmatter. Verified on a verification branch.
- **SC-004**: The watcher correctly classifies a stalled session (artificially hung skill) and terminates within `stall_window + poll_interval` (default 5m 30s). Verified by a stalled-session fixture in the seed tests.
- **SC-005**: The watcher does NOT terminate a long-running but healthy session. Verified by running the harness against a >10-minute fixture that writes heartbeat files every 10 seconds and confirming no `stalled` verdict is emitted.
- **SC-006**: Fresh local edits to `plugin-kiln/skills/<skill>/SKILL.md` are picked up by the very next harness invocation with no `/plugin reload` and no cache flush. Verified by editing a seed skill in place and confirming the test behavior changes on the next run.
- **SC-007**: Scratch-dir isolation — the harness MUST NOT write outside `/tmp/kiln-test-<uuid>/` and the skill under test MUST NOT modify the plugin source tree. Verified by a test that deliberately attempts to write to `plugin-kiln/skills/kiln-distill/SKILL.md` during execution and asserts the write was contained or detected.
- **SC-008**: TAP output determinism — running the same test twice against unchanged source produces byte-identical stdout (UUIDs appear only in the verdict report, not in the TAP stream). Verified by a diff check.
- **SC-009**: The harness emits exit code 0 when all tests pass, 1 when any test fails, and 2 when any test is inconclusive. Verified by running against known-passing, known-failing, and known-malformed test sets.
- **SC-010**: Seed tests ship at the canonical discovery path (per plan Decision D1) and are invokable via `/kiln:kiln-test kiln` out of the box, with no additional setup beyond `claude` on PATH.

## Assumptions

- `claude` CLI is on PATH in every environment that runs the harness. `--plugin-dir`, `--headless`, `--dangerously-skip-permissions`, and `--initial-message` are the current flag names (Risk 4 in the PRD acknowledges these may drift; the plan wraps them in a single helper script).
- POSIX `find` and `sha256sum` are available (standard on all supported systems).
- UUIDv4 generation is available via `uuidgen` or an equivalent.
- The user of the harness trusts the tests + fixtures being run. V1 does not sandbox. Scratch-dir isolation is the safety boundary, and `--dangerously-skip-permissions` is acceptable within that boundary (per plan Decision D6).
- Heartbeat files (for skills doing long-running shell work) are a discipline, not a mechanism. The watcher treats any scratch-dir write as activity; a skill that wants to avoid `stalled` misclassification during a long `npm install` emits a heartbeat file.
- Tests ship in-tree with the plugin, not in a separate repo. Tests running against an external plugin require the user to clone that plugin's source.

## Dependencies

- Kiln plugin infrastructure (`plugin-kiln/skills/`, `plugin-kiln/agents/`, `plugin-kiln/scripts/`).
- Existing `.kiln/logs/` directory convention (verdict reports and scratch snapshots land here).
- Constitution Article VII (interface contracts) and VIII (incremental task completion) — enforced by existing hooks during implementation.
