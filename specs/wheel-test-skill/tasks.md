---
description: "Task breakdown for the wheel-test skill"
---

# Tasks: Wheel Test Skill

**Input**: Design documents from `/specs/wheel-test-skill/`
**Prerequisites**: `spec.md`, `plan.md`, `contracts/interfaces.md` (all committed before implementation starts)

**Tests**: This feature is a Markdown skill with inline Bash. There are no traditional unit tests — validation is end-to-end via running the skill itself against the real 12-workflow suite. This exemption is documented in `plan.md` under Complexity Tracking.

## Format: `[ID] [P?] [Story] Description`

- **[P]** — can run in parallel with other [P] tasks in the same phase (no shared files)
- **[Story]** — US1 (smoke test), US2 (diagnose), US3 (audit trail), or SETUP/POLISH

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the skill directory and stub SKILL.md so hooks can operate on the tree.

- [X] T001 [SETUP] Create `plugin-wheel/skills/wheel-test/` directory and stub `SKILL.md` with the kiln skill frontmatter (name, description, example invocations). Use `wheel-run`, `wheel-list`, or `wheel-status` as the formatting reference.
- [X] T002 [SETUP] Verify `.gitignore` already excludes `.wheel/logs/` (grep check). If missing, add `.wheel/logs/` to `.gitignore`. (Mitigation for Risk listed in plan.md.)
- [X] T003 [SETUP] Check `plugin-wheel/.claude-plugin/plugin.json` for how existing skills are declared. If the manifest explicitly lists skills, add `wheel-test` following the same pattern. If it uses auto-discovery, leave it alone. Document the choice in the SKILL.md header comment.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define the globals, preflight, and classification primitives. All user stories depend on these.

- [X] T004 [SETUP] Implement the read-only globals block per `contracts/interfaces.md` (`WT_REPO_ROOT`, `WT_TESTS_DIR`, `WT_WHEEL_DIR`, `WT_STATE_GLOB`, `WT_HISTORY_*`, `WT_LOG_FILE`, `WT_REPORT_DIR`, `WT_ACTIVATE_SH`, `WT_RUN_TIMESTAMP`, `WT_LOG_BASELINE`, `WT_START_EPOCH`) inside SKILL.md.
- [X] T005 [SETUP] Implement `wt_init_run_clock` (sets `WT_RUN_TIMESTAMP` via `date -u +%Y%m%dT%H%M%SZ` and `WT_START_EPOCH` via `date +%s`).
- [X] T006 [SETUP] Implement `wt_require_nonempty_tests_dir` (FR-014). Non-zero exit with a clear stderr message when `workflows/tests/` has no `.json` files.
- [X] T007 [SETUP] Implement `wt_discover_workflows` (FR-001) — prints absolute paths of all `workflows/tests/*.json`, newline-separated.
- [X] T008 [SETUP] Implement `wt_require_clean_state` (FR-007) — lists any `.wheel/state_*.json` and refuses to proceed if non-empty.
- [X] T009 [SETUP] Implement `wt_record_log_baseline` (FR-009) — prints line count of `.wheel/logs/wheel.log`, 0 if missing.
- [X] T010 [SETUP] Implement `wt_step_types` — `jq -r '.steps[].type' <file> | sort -u`.
- [X] T011 [SETUP] Implement `wt_classify_workflow` (FR-002) applying precedence: `team-*`/`teammate` → 4; `workflow` → 3; `agent` → 2; else → 1. Classification MUST read JSON step types, NOT the filename.
- [X] T012 [SETUP] Implement `wt_expected_outcome` (FR-005) — basename-glob check for `*-fail*`.
- [X] T013 [SETUP] Implement `wt_record_result` — appends a TAB-separated row to `${WT_WHEEL_DIR}/logs/.wheel-test-results-${WT_RUN_TIMESTAMP}.tsv`. Replace any embedded TABs in `notes` with spaces before writing.

**Checkpoint**: Foundation ready. User story phases can begin.

---

## Phase 3: User Story 1 — Smoke test after a wheel-engine change (P1) 🎯 MVP

**Goal**: A developer invokes `/wheel-test` and gets a pass/fail verdict in under 5 minutes covering every workflow in `workflows/tests/`.

**Independent Test**: From a clean state, run `/wheel-test`. Verify the skill classifies all workflows, runs each phase, writes a report, and emits a final PASS/FAIL line.

### Execution primitives

- [X] T014 [US1] Implement `wt_activate` (FR-003/FR-004) — calls `${WT_ACTIVATE_SH} "$1"` and returns its exit code. Prints the workflow basename to stdout. NOTE: kept in `runtime.sh` as a reference, but SKILL.md does NOT call it — see T017 note.
- [X] T015 [US1] Implement `wt_wait_for_archive` (FR-010, FR-015) — polls `success/`, `failure/`, `stopped/` every 1s for a file matching `{basename}-*-*.json` (hybrid format). Timeout handling prints `TIMEOUT` and returns 2. Missing-state-file-but-no-archive case prints `MISSING` and returns 3.
- [X] T016 [US1] Implement `wt_detect_orphans` (FR-008) — lists any `.wheel/state_*.json` matching the glob. Returns 0 always.

### Phase 1 parallel runner

- [X] T017 [US1] ~~Implement `wt_run_phase1`~~ **CONTRACT CHANGE** — replaced with `wt_phase1_wait_all` + `wt_record_phase1_start` + `wt_load_run_env` helpers. The wheel PostToolUse hook processes only the last `activate.sh` line per Bash tool call (`tail -1` in `post-tool-use.sh`) AND its regex rejects quoted-variable paths like `"$VAR"/activate.sh`, so a shell function that loops activate.sh calls cannot work. Activation is now the skill invoker's responsibility: one Bash tool call per workflow with a LITERAL absolute path. See SKILL.md Step 2. Contract updated in `contracts/interfaces.md` with full explanation.

### Phases 2–4 serial runner

- [X] T018 [US1] ~~Implement `wt_run_serial_phase`~~ **CONTRACT CHANGE** — replaced with `wt_wait_and_record_serial` (single-workflow waiter). Same root cause as T017. SKILL.md Steps 4/5/6 instruct the invoker to issue per-workflow Bash tool calls: literal activate.sh, then wt_wait_and_record_serial. Phase 4 folds in the stop-hook ceremony between activate and wait.
- [X] T019 [US1] In SKILL.md, write the Phase 4 stop-hook ceremony instruction block (FR-006). Explicitly enumerate: (1) activate, (2) wait for TeamCreate instruction from the stop hook, (3) call TeamCreate, (4) wait for spawn instructions, (5) spawn teammates via the Agent tool with `run_in_background: true`, (6) wait for teammate results, (7) send `shutdown_request` to each teammate, (8) wait for `teammate_terminated` notifications, (9) call TeamDelete, (10) wait for archive. Include an explicit "blind-spawning before the stop-hook instruction arrives is forbidden" warning tied to the bug trail.

### Top-level orchestration

- [X] T020 [US1] In SKILL.md, wire together the top-level flow: preflight → classify all (Step 1) → per-workflow activations + waits (Steps 2-6) → reconcile + build report + emit + verdict (Step 7). Classification output drives which workflows go in which step.
- [X] T021 [US1] Implement `wt_final_verdict` (FR-013) — reads the TSV accumulator, counts pass/fail/orphan rows, counts hook errors via `wt_collect_hook_errors`, prints `PASS` or `FAIL (M failed, K orphaned, L hook errors)`, returns 0 on PASS else 1.

**Checkpoint**: US1 is functional. A developer can invoke `/wheel-test` and get a final verdict line, though the report body is not yet complete — US2 delivers the diagnostic detail.

---

## Phase 4: User Story 2 — Diagnose a regression (P2)

**Goal**: The report explains WHY a workflow failed — phase, orphans, hook errors, notes.

**Independent Test**: Break one workflow, run `/wheel-test`, confirm the report names the broken workflow, its phase, any orphans, and any hook errors.

- [X] T022 [US2] Implement `wt_collect_hook_errors` (FR-009) — tails `.wheel/logs/wheel.log` from `WT_LOG_BASELINE + 1` to EOF with `tail -n +N`, filters via `grep -E 'ERROR|FAIL|stalled'`, prints matches to stdout.
- [X] T023 [US2] Implement `wt_reconcile_expected_failures` (FR-005) — rewrites the TSV accumulator so expected-failure workflows that archived to `failure/` become `pass` with a note, and expected-success workflows that archived to `failure/` are `fail`. Also maps `stopped` status to `fail` with the "stopped unexpectedly" note (FR-018).
- [X] T024 [US2] Implement `wt_build_report` (FR-011) — prints the full markdown: H1 header with timestamp, metadata block, summary counts, per-workflow table (columns: Workflow | Phase | Expected | Status | Duration | Archive | Notes), orphan section (only if orphans present), hook error section (only if hook errors present), reproduction commands section listing one `./plugin-wheel/bin/activate.sh <absolute-path>` per workflow.

**Checkpoint**: A failing run produces a useful report a developer can diff and debug from.

---

## Phase 5: User Story 3 — Audit trail (P3)

**Goal**: Every run persists a timestamped report that never overwrites previous runs.

**Independent Test**: Run `/wheel-test` twice, see two distinct files under `.wheel/logs/test-run-*.md`.

- [X] T025 [US3] Implement `wt_emit_report` (FR-012) — writes `$1` (markdown body) to `${WT_REPORT_DIR}/test-run-${WT_RUN_TIMESTAMP}.md`, echoes the body to stdout, and prints the absolute report path on the last line. Because `WT_RUN_TIMESTAMP` includes seconds, back-to-back runs produce distinct files.

**Checkpoint**: All three user stories complete.

---

## Phase 6: Polish & Cross-Cutting

- [X] T026 [POLISH] SKILL.md documentation pass: every function in `lib/runtime.sh` has a one-line FR reference comment; SKILL.md top matches plan.md's Phase Execution Model (table + Absolute Musts list).
- [X] T027 [POLISH] File size check: SKILL.md is 250 lines (under 500). `lib/runtime.sh` at 573 lines is a single helper library (not SKILL.md), so Principle VI's 500-line-per-skill-file guideline is satisfied. No extraction needed.
- [X] T028 [POLISH] validate-workflow.sh not used by wheel-test — classification reads JSON step types directly via `jq`. Documented in SKILL.md Step 1 / runtime.sh `wt_step_types`. No dependency to verify.
- [X] T029 [POLISH] Smoke verification — completed by audit-smoke teammate. Static verification of all 12 workflows classified correctly, all 21 wt_* contract functions present, bash -n clean, SKILL.md Step 6 stop-hook ceremony verified. Full end-to-end execution was explicitly out of scope per team-lead brief. Evidence: `specs/wheel-test-skill/agent-notes/audit-smoke.md`.
- [X] T030 [POLISH] Verify `.wheel/state_*.json` is empty — completed by audit-smoke teammate (see audit-smoke.md check #11: state glob empty, precondition satisfied).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)** — no prerequisites; T001–T003 can start immediately.
- **Phase 2 (Foundational)** — depends on Phase 1. T004 precedes T005–T013.
- **Phase 3 (US1)** — depends on Phase 2. T014–T021 sequential, with T020 requiring T014–T019 and T021 requiring T020.
- **Phase 4 (US2)** — depends on Phase 3 completing. T022 and T023 can run in parallel [P]; T024 depends on both.
- **Phase 5 (US3)** — depends on Phase 4 for `wt_build_report` output. T025 is the sole task.
- **Phase 6 (Polish)** — depends on all user stories complete.

### Within each user story

- T017 (`wt_run_phase1`) depends on T014, T015, T016.
- T018 (`wt_run_serial_phase`) depends on T014, T015, T016, T019.
- T020 (wiring) depends on T011, T012, T017, T018.
- T021 (`wt_final_verdict`) depends on T013 and T024 (it reads hook error counts from report data).
- T024 (`wt_build_report`) depends on T022 and T023.

### Parallel opportunities

- **Phase 1**: T001, T002, T003 are different concerns; T002 and T003 can run in parallel after T001.
- **Phase 2**: T010, T011, T012 can run in parallel after T004 ([P]).
- **Phase 4**: T022 and T023 can run in parallel ([P]) before T024.

---

## Notes

- [Story] label maps task to user story for traceability.
- Mark `[X]` immediately on completion per Principle VIII. Do not batch.
- Commit after each completed phase (Principle VIII).
- The skill intentionally has no mock mode — validation is end-to-end only (Absolute Must #5).
- All workflow progression MUST go through `activate.sh` + hooks. Never write state files or cursors from inside the skill (Absolute Must #2, FR-016).
- Classification MUST read JSON step types, never the filename (Absolute Must #3, FR-002).
- `.wheel/state_*.json` MUST be empty after a successful run (Absolute Must #4, FR-017, SC-004).
