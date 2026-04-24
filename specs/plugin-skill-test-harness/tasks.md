---

description: "Task list for plugin-skill-test-harness (single implementer, phase-ordered, contract-driven)"
---

# Tasks: Plugin Skill Test Harness

**Input**: Design documents from `/specs/plugin-skill-test-harness/`
**Prerequisites**: spec.md (✅), plan.md (✅), contracts/interfaces.md (✅)

**Team shape**: Single implementer owns everything. Phases A→H run sequentially; tasks marked [P] within a phase are parallelizable (no file overlap) but sequencing doesn't meaningfully speed up a single implementer.

**Traceability**: Every task names the FRs it satisfies + the interfaces.md section it implements. Every script signature matches section 7 of contracts/interfaces.md verbatim.

**Contract version**: Interface contracts are at **v1.1** (bumped 2026-04-23 to resolve BLOCKER-001). All tasks that reference `claude-invoke.sh` / watcher classifications / FIFO now use the stream-json envelope design per contracts §7.2 + §3 + §5 and plan.md D6. Specifically: T008, T011, T012, T014 are implementing the stream-json + up-front-answers design, NOT the original `--headless` + FIFO design.

## Format: `[ID] [P?] Description`

- **[P]**: Different files from previous task in same phase; can run in parallel with a sibling [P].
- Task IDs are sequential (T001..T017).

---

## Phase A — Skeleton + scratch lifecycle + TAP emitter (FR-001..005)

**Goal**: Harness can be invoked, discover tests, create+destroy scratch dirs, emit a TAP stream. No substrate yet — all tests emit `# SKIP substrate not implemented` placeholder at this phase-end checkpoint.

- [ ] **T001** Create directory skeleton: `plugin-kiln/skills/kiln-test/` (empty SKILL.md placeholder), `plugin-kiln/scripts/harness/` (empty), `plugin-kiln/tests/` (empty). Satisfies FR-001 directory layout. Ref: plan.md Project Structure.

- [ ] **T002** Implement `plugin-kiln/scripts/harness/scratch-create.sh` per contracts §7.5. UUIDv4 gen, collision retry (3 attempts), exit 2 on 4th failure. Satisfies FR-003 scratch-dir path invariant.

- [ ] **T003** Implement `plugin-kiln/scripts/harness/fixture-seeder.sh` per contracts §7.1. Recursive `cp -R` from `<test-dir>/fixtures/` to `<scratch-dir>/`; empty fixtures → exit 0; copy error → exit 2. Satisfies FR-002 fixture copy step.

- [ ] **T004** Implement `plugin-kiln/scripts/harness/tap-emit.sh` per contracts §7.3. Supports `pass`, `fail` (with YAML diagnostic file), `skip` (reason-from-diagnostic). Strict stdout-only; no stderr. Satisfies FR-004 TAP v14 grammar + §2 of contracts.

- [ ] **T005** Implement `plugin-kiln/scripts/harness/test-yaml-validate.sh` per contracts §7.6 + §1 schema. Validates `harness-type` ∈ {`plugin-skill`}, `expected-exit` non-negative int (default 0), `description` non-empty, `timeout-override` ∈ [60, 3600] when present. Unknown top-level keys → warning, not failure. Satisfies FR-002 test.yaml contract.

- [ ] **T006** Implement `plugin-kiln/scripts/harness/config-load.sh` per contracts §7.7. Reads `.kiln/test.config` if present; emits key=value. Defaults: `watcher_stall_window_seconds=300`, `watcher_poll_interval_seconds=30`. Satisfies FR-014 config override contract.

- [ ] **T007** Implement `plugin-kiln/scripts/harness/kiln-test.sh` per contracts §7.11. Plugin auto-detect (sibling `plugin-<name>/` scan → exit 2 with plugin-list diagnostic if multi-plugin), test discovery under `plugin-<name>/tests/`, TAP header `TAP version 14\n1..N\n`, loop over tests emitting placeholder `# SKIP substrate-not-yet-wired`, aggregate exit per contracts §2. Satisfies FR-001 all three invocation forms (skeleton level) and FR-005 exit-code aggregation.

**Phase A checkpoint**: `/kiln:kiln-test` discovers tests and emits a well-formed TAP stream with all `# SKIP` lines. Exit code 2 (inconclusive). Commit: "phase A: harness skeleton + scratch lifecycle + TAP emitter".

---

## Phase B — plugin-skill substrate driver (FR-009..012)

**Goal**: The `plugin-skill` substrate can spawn a real `claude --plugin-dir ... --headless` subprocess, wire the scratch dir as CWD, set `KILN_HARNESS=1`, and snapshot the final scratch state. Watcher is not yet wired — substrate runs without classification.

- [ ] **T008** Implement `plugin-kiln/scripts/harness/claude-invoke.sh` per contracts §7.2. Header comment documents the current CLI flag contract (`--plugin-dir`, `--headless`, `--dangerously-skip-permissions`, `--initial-message`) per PRD Risk 4. Spawns subprocess with CWD=scratch-dir, env `KILN_HARNESS=1`, stdin inherited. Satisfies FR-009 subprocess invocation + FR-011 env + NFR-001 portability (uses `${WORKFLOW_PLUGIN_DIR}` in SKILL.md callers, but this script itself is callable by absolute path).

- [ ] **T009** [P] Implement `plugin-kiln/scripts/harness/scratch-snapshot.sh` per contracts §7.4. `find -type f` + sha256sum, path-sorted, writes to `<output-path>`. Satisfies FR-012 diagnostic snapshot.

- [ ] **T010** Implement `plugin-kiln/scripts/harness/dispatch-substrate.sh` per contracts §5. V1 single-case switch: `plugin-skill` → `substrate-plugin-skill.sh`; unknown → exit 2 with `"Substrate '<type>' not implemented in v1"` diagnostic. Satisfies FR-002 substrate tag + plan.md substrate abstraction.

- [ ] **T011** Implement `plugin-kiln/scripts/harness/substrate-plugin-skill.sh` per contracts §5 v1 substrate spec. Reads `inputs/initial-message.txt`, calls `claude-invoke.sh` with the FIFO for scripted-answer input, waits for subprocess exit, propagates exit code. Satisfies FR-009 + FR-010 stdin-pipe prep.

**Phase B checkpoint**: Wire substrate into `kiln-test.sh` loop. A test whose `assertions.sh` is `#!/bin/bash\nexit 0` should PASS end-to-end now (subprocess runs, assertions pass, TAP emits `ok`). Commit: "phase B: plugin-skill substrate driver".

---

## Phase C — Watcher agent + verdict reporter (FR-006..008)

**Goal**: Haiku-model classifier replaces hard timeouts. Detects `healthy` / `paused` / `stalled` / `failed`. On `paused`, feeds `answers.txt` lines to subprocess stdin via FIFO. On terminal classification, writes verdict JSON + human-readable report.

- [ ] **T012** Create `plugin-kiln/agents/test-watcher.md` per plan Decision D5. Model: `haiku`. System prompt defines: classification schema (contracts §3), poll cadence (D3), terminal-transition emission rules, pause-prompt extraction regex (contracts §3 classification rules). Matches other kiln agents' format (compare `plugin-kiln/agents/debugger.md`, `plugin-kiln/agents/qa-engineer.md`). Satisfies FR-006 watcher contract + FR-008 no-hard-caps.

- [ ] **T013** [P] Implement `plugin-kiln/scripts/harness/watcher-poll.sh` per contracts §7.10. Samples scratch dir mtime, transcript tail, subprocess PID status; emits snapshot JSON. No classification — the agent owns that. Satisfies FR-006 poll mechanism.

- [ ] **T014** Implement `plugin-kiln/scripts/harness/watcher-runner.sh` per contracts §7.9. Spawns the `test-watcher` agent with the polling loop. On `paused` verdict: reads next `inputs/answers.txt` line and writes to stdin FIFO (or fails test with `paused-exhausted` classification per contracts §6 if exhausted). On `stalled` / `failed`: writes verdict JSON + human-readable `.kiln/logs/kiln-test-<uuid>.md` report per FR-007, then sends SIGTERM to subprocess. Wire into `kiln-test.sh` main loop so substrate + watcher run concurrently per test. Satisfies FR-006, FR-007, FR-010.

**Phase C checkpoint**: Watcher is live. A fixture that deliberately hangs produces a `stalled` verdict within `stall_window + poll_interval` (5m 30s default). A fixture that emits a prompt pattern gets answered from `answers.txt`. Commit: "phase C: watcher agent + verdict reporter".

---

## Phase D — `/kiln:kiln-test` skill body (FR-001)

**Goal**: User-facing skill exists and is portable (NFR-001).

- [ ] **T015** Write `plugin-kiln/skills/kiln-test/SKILL.md`. Frontmatter: `name: kiln-test`, description reflecting invocation forms. Body describes the three invocation forms (FR-001), refers to helper scripts via `${WORKFLOW_PLUGIN_DIR}/scripts/harness/...` (NFR-001 portability — NO repo-relative `plugin-kiln/scripts/...` paths). Body delegates to `kiln-test.sh` orchestrator. Includes the check for `claude` on PATH (Edge Cases). Satisfies FR-001 + NFR-001.

---

## Phase E — Consumer contract + auto-detection polish (FR-013..014)

**Goal**: Harness runs cleanly in a fresh source-repo checkout with defaults; `.kiln/test.config` overrides work.

- [ ] **T016** Add consumer-facing docs inside `plugin-kiln/skills/kiln-test/SKILL.md` (same file — extend Phase D body) describing: discovery path override via `.kiln/test.config`, the required-on-PATH `claude` CLI dep (NFR-002), and an example `.kiln/test.config` showing all three default keys. Also extend `kiln-test.sh` (T007 file) to surface config-load errors with exit 2 and a diagnostic. Satisfies FR-013 + FR-014.

---

## Phase F — Seed tests (FR-015)

**Goal**: Two executable tests ship that demonstrate the harness against real kiln skills.

- [ ] **T017** [P] Ship `plugin-kiln/tests/kiln-distill-basic/`: `test.yaml` (harness-type: plugin-skill, skill-under-test: kiln:kiln-distill, expected-exit: 0), `fixtures/.kiln/issues/` with 3 seed backlog items + `fixtures/.kiln/feedback/` with 1 seed feedback item, `inputs/initial-message.txt` = `/kiln:kiln-distill`, `inputs/answers.txt` with scripted answers for any distill prompts, `assertions.sh` that greps the generated PRD for expected frontmatter keys (`derived_from:`) and expected body sections. Satisfies FR-015 first seed + SC-001.

- [ ] **T018** [P] Ship `plugin-kiln/tests/kiln-hygiene-backfill-idempotent/`: `test.yaml` (harness-type: plugin-skill, skill-under-test: kiln:kiln-hygiene, expected-exit: 0), `fixtures/specs/` containing 2-3 merged-PRD directories missing `derived_from:` frontmatter, `inputs/initial-message.txt` that invokes `/kiln:kiln-hygiene backfill` twice in sequence and captures both log paths, `inputs/answers.txt` empty or with confirm-y lines, `assertions.sh` that greps the SECOND log for `^diff --git ` and fails if any match. Satisfies FR-015 second seed + SC-002 idempotence regression test.

**Phase F checkpoint**: Both seed tests pass when run via `/kiln:kiln-test kiln`. Commit: "phase F: seed tests (distill-basic, hygiene-backfill-idempotent)".

---

## Phase G — CLAUDE.md entry

**Goal**: Consumer discovery of the new command.

- [ ] **T019** Edit `CLAUDE.md` under "Available Commands" → "Other" section. Add:

  `- /kiln:kiln-test [plugin] [test] — Executable skill-test harness. Invokes real claude --plugin-dir ... --headless subprocesses against /tmp/kiln-test-<uuid>/ fixtures, watched by a classifier agent (no hard timeouts). Three forms: /kiln:kiln-test (auto-detect plugin), /kiln:kiln-test <plugin>, /kiln:kiln-test <plugin> <test>. Seed tests under plugin-kiln/tests/. Verdict reports at .kiln/logs/kiln-test-<uuid>.md. V1: plugin-skill substrate only.`

  Does not touch Recent Changes (the retrospective agent will).

---

## Phase H — SMOKE.md meta-fixtures

**Goal**: The harness tests *itself* via executable fixtures that invoke it against the two seed tests and verify exit codes / TAP shape. This is the harness's own test harness.

- [ ] **T020** Write `specs/plugin-skill-test-harness/SMOKE.md`. Contents: three executable bash blocks that (a) run `/kiln:kiln-test kiln kiln-distill-basic` and verify stdout matches `^ok 1 - kiln-distill-basic$` and exit code 0; (b) run `/kiln:kiln-test kiln kiln-hygiene-backfill-idempotent` and verify `^ok 1 - kiln-hygiene-backfill-idempotent$` and exit code 0; (c) run `/kiln:kiln-test kiln` (full plugin suite) and verify exit code 0 with `1..2` plan line. Each block is self-contained and greppable for CI adoption later. Satisfies SC-001, SC-002, SC-009, SC-010.

**Phase H checkpoint**: SMOKE.md blocks execute cleanly when pasted into a shell. This is the gate that proves the harness actually works — the long-standing retrospective gap closes here. Commit: "phase H: SMOKE.md meta-fixtures + retrospective-gap closure".

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase A** — no deps, starts immediately
- **Phase B** — blocked by A (needs TAP emitter + scratch lifecycle + kiln-test.sh main loop to wire substrate into)
- **Phase C** — blocked by B (watcher needs subprocess to watch; FIFO stdin hook lives in substrate-plugin-skill.sh)
- **Phase D** — can overlap with C (SKILL.md is independent of watcher internals), but recommend writing after C so the SKILL.md body can reference the real behavior
- **Phase E** — blocked by D (extends the skill body)
- **Phase F** — blocked by B (needs a working substrate to execute); seed-test assertion design depends on C watcher behavior for SC-004 / SC-005
- **Phase G** — trivially independent; can commit alongside F
- **Phase H** — blocked by F (tests the seed tests)

### Task-level parallelism

- T002/T003/T004 are all in Phase A and touch different files; can be written in parallel by a single implementer via batched edits, but the intended sequence is T002 (scratch) → T003 (seeder) → T004 (TAP emit) → T005 (yaml validate) → T006 (config) → T007 (orchestrator wires them all).
- T009 is marked [P] — `scratch-snapshot.sh` is an independent file from T008's `claude-invoke.sh`.
- T013 is marked [P] — `watcher-poll.sh` is independent from T012's agent markdown.
- T017 + T018 are both [P] — different seed test directories.

---

## Implementation Strategy

### Gate cadence (Article VIII — incremental completion)

Commit after each phase checkpoint. That's 8 commits for the whole feature. Do NOT batch — the `/implement` hooks will block large edits without intermediate `[X]` task marks.

### Self-validation at each checkpoint

- **After A**: `/kiln:kiln-test` emits a well-formed TAP v14 stream with all `# SKIP` lines against an empty `plugin-kiln/tests/`.
- **After B**: A trivial pass-test with `assertions.sh = exit 0` emits `ok 1 - trivial`.
- **After C**: A hang-test fixture is classified `stalled` within 5m 30s. A prompt-emitting fixture consumes the correct `answers.txt` line.
- **After F**: Both seed tests pass end-to-end.
- **After H**: SMOKE.md blocks pass when pasted into a shell.

### PR audit

After T020, run the PRD audit sub-loop (this is what the auditor teammate does on Task #3). Every FR-001..015, NFR-001..006, SC-001..010 must be either passing or explicitly blocked with documented rationale.

---

## Traceability matrix

| FR / SC | Task(s) |
|---------|---------|
| FR-001 (three invocation forms + skill exists) | T001, T007, T015 |
| FR-002 (test dir layout, test.yaml) | T003, T005 |
| FR-003 (scratch dir `/tmp/kiln-test-<uuid>/`) | T002 |
| FR-004 (TAP v14 output) | T004 |
| FR-005 (exit codes 0/1/2) | T004, T007 |
| FR-006 (watcher agent + classifications) | T012, T013, T014 |
| FR-007 (verdict report `.kiln/logs/`) | T014 |
| FR-008 (no hard caps) | T012, T014 |
| FR-009 (claude subprocess spawn) | T008, T011 |
| FR-010 (answers.txt FIFO) | T011, T014 |
| FR-011 (`KILN_HARNESS=1`) | T008 |
| FR-012 (scratch snapshot) | T009, T011 |
| FR-013 (consumer contract) | T015, T016 |
| FR-014 (config overrides) | T006, T016 |
| FR-015 (two seed tests) | T017, T018 |
| NFR-001 (`${WORKFLOW_PLUGIN_DIR}` portability) | T015, T016 |
| NFR-002 (no MCP/gh deps) | reviewed at T019 CLAUDE.md edit |
| NFR-003 (determinism) | T004 (UUIDs not in TAP) |
| NFR-004 (isolation) | T002, T011 |
| NFR-005 (SMOKE.md left alone) | verified at audit |
| NFR-006 (per-test invocation form) | T007, T015 |
| SC-001 | T017 + T020 |
| SC-002 | T018 + T020 |
| SC-003 | T017 (verification branch — documented in T020 SMOKE.md) |
| SC-004 | T012, T014 |
| SC-005 | T012, T014 |
| SC-006 | T008 (no cache flush needed) |
| SC-007 | T002, T011 |
| SC-008 | T004 |
| SC-009 | T004, T007, T020 |
| SC-010 | T017, T018, T020 |

---

## Notes

- No `[Story]` label on tasks — the 3 user stories in spec.md all depend on the full harness; splitting tasks by story would fragment tightly-coupled components.
- Every bash script uses `set -euo pipefail`.
- Every helper-script signature in Phase A–C matches contracts/interfaces.md §7 verbatim; deviation is an Article VII violation.
- Commit cadence: 8 commits (one per phase checkpoint). Task-level `[X]` marks MUST happen immediately on completion per Article VIII.
