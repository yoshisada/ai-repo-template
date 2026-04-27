---
description: "Task list for vision-tooling feature implementation"
---

# Tasks: Vision Tooling — Cheap to Update, Drift-Checked, Forward-Projecting, Measurable

**Input**: Design documents from `specs/vision-tooling/`
**Prerequisites**: spec.md, plan.md, contracts/interfaces.md (all present)

**Tests**: REQUIRED. NFR-004 mandates ≥80% coverage on new code; PR #189's shell-only fixture-and-assertion-block convention is the substrate. Each user story carries its own `plugin-kiln/tests/<feature>/run.sh` fixture.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing. Theme A (US1) is the MVP; B+C (US2+US3) and D (US4) ship in subsequent increments.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Different files, no dependencies on incomplete tasks — safe to parallelize.
- **[Story]**: `[US1]` Theme A simple-params, `[US2]` Theme B alignment check, `[US3]` Theme C forward-pass, `[US4]` Theme D scorecard.
- Every implementation task references its FR(s) and the contract entry in `specs/vision-tooling/contracts/interfaces.md`.

## Path Conventions

This is the plugin source repo. All code lives under `plugin-kiln/`. Tests live under `plugin-kiln/tests/<feature>/run.sh`. No `src/`, no `tests/` at repo root (that structure exists only in consumer scaffolds).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Capture the byte-identity baseline (NFR-005 / SC-009) BEFORE any code edits, plus add gitignore + plugin-manifest scaffolding that every later phase depends on.

**⚠️ CRITICAL**: T001 MUST complete before ANY edits to `plugin-kiln/skills/kiln-roadmap/SKILL.md`. If T001 is skipped, Theme A's back-compat assertion is unauthorable and SC-009 cannot pass.

- [X] T001 Capture pre-PRD coached-interview baseline at `plugin-kiln/tests/vision-coached-back-compat/fixtures/pre-prd-coached-output.txt` by running the current (unedited) `/kiln:kiln-roadmap --vision` against a frozen fixture vision file under `plugin-kiln/tests/vision-coached-back-compat/fixtures/vision.md`; commit both fixture inputs and the captured output. *(NFR-005, SC-009; risk R-4 mitigation)*
- [X] T002 [P] Add `.kiln/.vision.lock` to `.gitignore` (verify `.kiln/logs/` already ignored; if not, add it). *(NFR-003 lockfile gitignore; FR-019 log dir gitignore)*
- [X] T003 [P] Create empty directory marker `plugin-kiln/scripts/metrics/.gitkeep` so the new metrics dir lands cleanly when Theme D ships.
- [X] T004 [P] Create empty directory marker `.kiln/roadmap/items/declined/.gitkeep` so Theme C's first decline lands without dir-creation race. *(FR-022)*

**Checkpoint**: Baseline captured. Lock + log gitignore in place. Sub-directories pre-created. Code edits to `kiln-roadmap/SKILL.md` are now safe.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Section-flag mapping table (FR-021) + flag validator (FR-005) are shared by Theme A and the prompt-emission guard for Theme C (which checks "is any simple-params flag present? → no forward-pass"). Both must exist before Theme A's writer is wired up and before Theme C's guard test can pass.

- [X] T005 [P] Implement `plugin-kiln/scripts/roadmap/vision-section-flag-map.sh` per `contracts/interfaces.md` §"Theme A — vision-section-flag-map.sh". Sourceable + CLI-mode `--list`. Exports `VISION_FLAG_TO_SECTION` and `VISION_FLAG_OP` arrays. *(FR-021)*
- [X] T006 [P] Implement `plugin-kiln/scripts/roadmap/vision-flag-validator.sh` per `contracts/interfaces.md` §"Theme A — vision-flag-validator.sh". Stdout = canonical flag + tab + value; exit 2 on conflict / unknown / empty value; exit 0 with empty stdout when no simple-params flags present (caller dispatches coached interview). *(FR-005)*

**Checkpoint**: Mapping table + validator are deterministic, independently unit-testable, and unblock all four user stories.

---

## Phase 3: User Story 1 — Theme A: Simple-params CLI (Priority: P1) 🎯 MVP

**Goal**: `/kiln:kiln-roadmap --vision --add-* / --update-*` works end-to-end. Atomic temp+mv writes with `.kiln/.vision.lock`. `last_updated:` bumps before body change. Shelf mirror dispatch fires when configured; warn-and-continue otherwise. Flag conflicts refused before any I/O. Heavyweight coached interview SKIPPED on any simple-params flag.

**Independent Test**: Run `/kiln:kiln-roadmap --vision --add-constraint "Test — <UTC>"` against a fixture; assert SC-001 (3-second budget, last_updated bump, verbatim text), SC-002 (flag-conflict refusal + empty diff), FR-004 warn-and-continue, FR-001 final sentence (interview skip), and SC-009 (NFR-005 byte-identity to T001 baseline).

### Tests for User Story 1

- [X] T007 [P] [US1] Author `plugin-kiln/tests/vision-simple-params/run.sh` with assertion blocks for: SC-001 (a)-(d) (bullet under right section, last_updated bump, verbatim text, <3s wall-clock); SC-002 (flag-conflict refusal + `git diff` empty); FR-004 missing-`.shelf-config` warn-and-continue; FR-001 last sentence (no coached interview prompt emitted on simple-params path); FR-005 unknown-flag rejection. Target ≥12 assertion blocks per plan §Constitution Check Article II. *(NFR-004)* — actual: 32 assertion blocks PASS.
- [X] T008 [P] [US1] Author `plugin-kiln/tests/vision-coached-back-compat/run.sh` to assert that `/kiln:kiln-roadmap --vision` with NO new flags produces stdout + `vision.md` mutation byte-identical to the T001 fixture. *(SC-009, NFR-005)* — actual: 16 assertion blocks PASS.

### Implementation for User Story 1

- [X] T009 [US1] Implement `plugin-kiln/scripts/roadmap/vision-write-section.sh` per `contracts/interfaces.md` §"Theme A — vision-write-section.sh". Atomic temp+mv. `.kiln/.vision.lock` via `flock`-when-available, ±1 drift on macOS (mirror `plugin-shelf/scripts/shelf-counter.sh`). Bumps `last_updated:` to `date -u +%Y-%m-%d` BEFORE body mutation; both land in single atomic mv. Vision file byte-identical to pre-state on any non-zero exit. *(FR-001, FR-002, FR-003, NFR-003)*
- [X] T010 [P] [US1] Implement `plugin-kiln/scripts/roadmap/vision-shelf-dispatch.sh` per `contracts/interfaces.md` §"Theme A — vision-shelf-dispatch.sh". Reuses existing coached-interview shelf dispatch verbatim; warn-and-continue (exit 0 with single-line warning) when `.shelf-config` missing/incomplete. *(FR-004)*
- [X] T011 [US1] Edit `plugin-kiln/skills/kiln-roadmap/SKILL.md` to add the simple-params dispatch tree per `contracts/interfaces.md` §"plugin-kiln/skills/kiln-roadmap/SKILL.md (MODIFIED)" step 2: validator → write → shelf-dispatch → exit; SKIP coached interview on any simple-params flag. Update `--help` to enumerate new flags. Preserve byte-identical pre-PRD path when no new flags present. *(FR-001, FR-002, FR-005, NFR-005, FR-014)*

**Checkpoint**: Theme A is independently shippable. SC-001, SC-002, SC-009 verifiable via T007 + T008. MVP is at parity with PRD goal #1 (cheap updates).

---

## Phase 4: User Story 2 — Theme B: Vision-alignment check (Priority: P2)

**Goal**: `/kiln:kiln-roadmap --check-vision-alignment` walks open `.kiln/roadmap/items/`, LLM-maps each to vision pillars, emits a 3-section report (Aligned / Multi-aligned / Drifters) with the inference-caveat header verbatim. Report-only — never mutates anything.

**Independent Test**: Run `--check-vision-alignment` against a fixture; assert SC-003 (3 sections in order, caveat header verbatim, empty `git diff`), FR-006 (shipped items excluded), FR-008 (multi-aligned section populated when fixture has dual-pillar item), FR-009 (no mutation).

### Tests for User Story 2

- [X] T012 [P] [US2] Author `plugin-kiln/tests/vision-alignment-check/run.sh` with mock-LLM fixtures under `plugin-kiln/tests/vision-alignment-check/mock-llm/` (one `<basename>.txt` per fixture item). Set `KILN_TEST_MOCK_LLM_DIR` to the mock dir. Assertion blocks for: SC-003 caveat header verbatim, three sections in correct order, sort-by-item-id ASC, empty `git diff` post-run; FR-006 shipped items excluded; FR-008 multi-aligned populated; FR-009 no file mutation. Target ≥8 assertion blocks. *(NFR-004)*

### Implementation for User Story 2

- [X] T013 [P] [US2] Implement `plugin-kiln/scripts/roadmap/vision-alignment-walk.sh` per `contracts/interfaces.md` §"Theme B — vision-alignment-walk.sh". Emits one path per line, sorted ASC. Filter: `status != shipped` AND `state != shipped`. *(FR-006)*
- [X] T014 [P] [US2] Implement `plugin-kiln/scripts/roadmap/vision-alignment-map.sh` per `contracts/interfaces.md` §"Theme B — vision-alignment-map.sh". `claude --print` with `read-project-context.sh` grounding (PR #157). Honour `KILN_TEST_MOCK_LLM_DIR` mock-injection. Emits zero-or-more pillar-id lines on stdout. *(FR-007)*
- [X] T015 [US2] Implement `plugin-kiln/scripts/roadmap/vision-alignment-render.sh` per `contracts/interfaces.md` §"Theme B — vision-alignment-render.sh". Caveat header verbatim from FR-007. Three sections in fixed order; `(none)` body when a section is empty. Reads stdin in `<item-path>\t<pillar-list>` format. *(FR-008, FR-009)*
- [X] T016 [US2] Edit `plugin-kiln/skills/kiln-roadmap/SKILL.md` to add `--check-vision-alignment` mode per `contracts/interfaces.md` §"plugin-kiln/skills/kiln-roadmap/SKILL.md (MODIFIED)" step 3: walk → map per item → render → stdout. Coordinated with T011 + T020 to avoid skill-md conflicts (run T016 + T020 sequentially after T011). *(FR-006)*

**Checkpoint**: Theme B is shippable independently of A (already shipped in Phase 3) and Theme C/D. SC-003 verifiable.

---

## Phase 5: User Story 3 — Theme C: Forward-looking coaching (Priority: P2)

**Goal**: At the end of every coached `--vision` interview run, opt-in prompt offers ≤5 evidence-cited suggestions. Per-suggestion accept/decline/skip. Declined suggestions persist under `.kiln/roadmap/items/declined/` for next-pass dedup. Forward pass tied to coached path ONLY — never fires on simple-params.

**Independent Test**: Run a coached `--vision` interview to completion (against fixture vision.md) and answer the opt-in prompt with `y`; assert SC-004 (literal prompt, default-N exit), SC-005 (≤5 suggestions, required tags, evidence cites, accept/decline/skip routing), SC-006 (dedup on second run), SC-010 (simple-params path emits zero forward-pass prompts).

### Tests for User Story 3

- [X] T017 [P] [US3] Author `plugin-kiln/tests/vision-forward-pass/run.sh` with mock-LLM forward-pass fixture at `plugin-kiln/tests/vision-forward-pass/mock-llm/forward-pass.txt`. Drives the prompt with scripted stdin (`y`, `accept`/`decline`/`skip` selections). Assertion blocks for: SC-004 literal prompt + default-N early-exit; SC-005 tag-set validation + evidence-cite presence + ≤5 cap; SC-005 accept→`--promote` invocation, decline→declined-record file write, skip→nothing written; SC-006 dedup verified via two-pass run; SC-010 simple-params path stdout grep returns zero forward-pass-prompt matches. Target ≥10 assertion blocks. *(NFR-004)*

### Implementation for User Story 3

- [X] T018 [P] [US3] Implement `plugin-kiln/scripts/roadmap/vision-forward-dedup-load.sh` per `contracts/interfaces.md` §"Theme C — vision-forward-dedup-load.sh". Emits `<title>\t<tag>` lines from `.kiln/roadmap/items/declined/*.md`. Sorted ASC. Deterministic. *(FR-013)*
- [X] T019 [P] [US3] Implement `plugin-kiln/scripts/roadmap/vision-forward-pass.sh` per `contracts/interfaces.md` §"Theme C — vision-forward-pass.sh". `claude --print` with `read-project-context.sh` grounding. Honours `--declined-set` flag for dedup-exclusion. Honours `KILN_TEST_MOCK_LLM_DIR` mock-injection. Emits ≤5 four-line suggestion blocks separated by single blank line. *(FR-011, FR-013)*
- [X] T020 [P] [US3] Implement `plugin-kiln/scripts/roadmap/vision-forward-decision.sh` per `contracts/interfaces.md` §"Theme C — vision-forward-decision.sh". Reads single suggestion block on stdin; prompts on stderr; emits `accept|decline|skip` on stdout. *(FR-012)*
- [X] T021 [P] [US3] Implement `plugin-kiln/scripts/roadmap/vision-forward-decline-write.sh` per `contracts/interfaces.md` §"Theme C — vision-forward-decline-write.sh". Writes `kind: non-goal` declined-record under `.kiln/roadmap/items/declined/<date>-<slug>-considered-and-declined.md`. Slug-collision retry up to `-9`. *(FR-013, FR-022)*
- [X] T022 [US3] Edit `plugin-kiln/skills/kiln-roadmap/SKILL.md` to wire forward-pass into the END of the coached `--vision` interview tail per `contracts/interfaces.md` §"plugin-kiln/skills/kiln-roadmap/SKILL.md (MODIFIED)" step 4: emit literal opt-in prompt with default `N`; on `y`, load declined-set → run forward-pass → loop suggestions through decision → on accept invoke existing `--promote` hand-off, on decline invoke decline-write, on skip no-op. **Add the simple-params guard (FR-014) — when ANY simple-params flag is present, the forward-pass path MUST NOT execute.** Coordinated with T011 + T016 (sequential SKILL.md edits). *(FR-010, FR-012, FR-014, SC-010)*

**Checkpoint**: All four user-story P1+P2 paths shippable. SC-004, SC-005, SC-006, SC-010 verifiable.

---

## Phase 6: User Story 4 — Theme D: Win-condition scorecard (Priority: P3)

**Goal**: `/kiln:kiln-metrics` emits an 8-row scorecard (one per signal a–h) in the prescribed column shape. Graceful degrade to `unmeasurable` when an extractor can't measure. Report written to BOTH stdout AND `.kiln/logs/metrics-<timestamp>.md`.

**Independent Test**: Run `/kiln:kiln-metrics` on this repo; assert SC-007 (8 rows, prescribed columns, both stdout + log), SC-008 (force one extractor missing → unmeasurable + exit 0), FR-019 (timestamped log, no overwrite), FR-018 (each extractor invocable in isolation).

### Tests for User Story 4

- [X] T023 [P] [US4] Author `plugin-kiln/tests/kiln-metrics/run.sh` with `KILN_METRICS_NOW` set for timestamp determinism. Assertion blocks for: SC-007 8 rows + column shape + stdout==log; SC-008 missing-extractor → `unmeasurable` + exit 0; FR-019 log filename matches `metrics-<timestamp>.md` and second run with different `KILN_METRICS_NOW` does not overwrite first; FR-018 each `extract-signal-<x>.sh` runs standalone and emits the contract-shaped row line. Target ≥16 assertion blocks (≥2 per signal × 8 + global shape checks). *(NFR-004)*

### Implementation for User Story 4

- [X] T024 [P] [US4] Implement `plugin-kiln/scripts/metrics/render-row.sh` per `contracts/interfaces.md` §"Theme D — render-row.sh". Pipe-delimited row; escapes embedded `|`; rejects unknown `<status>` values with exit 2. *(FR-016)*
- [X] T025 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-a.sh` per per-signal evidence-source table in contracts. Emits one tab-separated success line OR `unmeasurable` line. Exit 0 on success, 4 on unmeasurable. *(FR-018, signal a)*
- [X] T026 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-b.sh` (escalations from `.wheel/history/`, 90-day window). *(FR-018, signal b)*
- [X] T027 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-c.sh` (capture surfaces → PRDs via `derived_from:`). *(FR-018, signal c)*
- [X] T028 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-d.sh` (mistake → manifest-improvement-landed via Obsidian `@inbox/closed/` read-only). *(FR-018, signal d)*
- [X] T029 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-e.sh` (`hook-*.log` blocked-edit + .env-commit count, 30-day window). *(FR-018, signal e)*
- [X] T030 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-f.sh` (shelf + trim sync drift count from latest audit logs). *(FR-018, signal f)*
- [X] T031 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-g.sh` (smoke-test pass rate from `plugin-kiln/tests/` records, 30-day window). *(FR-018, signal g)*
- [X] T032 [P] [US4] Implement `plugin-kiln/scripts/metrics/extract-signal-h.sh` (declined-records cross-referenced with `.kiln/feedback/` external sources). *(FR-018, signal h)*
- [X] T033 [US4] Implement `plugin-kiln/scripts/metrics/orchestrator.sh` per `contracts/interfaces.md` §"Theme D — orchestrator.sh". Walks each `extract-signal-{a..h}.sh`, catches non-zero exits and substitutes `unmeasurable`, calls `render-row.sh` per row, writes to stdout AND `.kiln/logs/metrics-<UTC-timestamp>.md`. Honours `KILN_METRICS_NOW` env var. Creates `.kiln/logs/` if missing. *(FR-015, FR-017, FR-019)*
- [X] T034 [US4] Create `plugin-kiln/skills/kiln-metrics/SKILL.md` per `contracts/interfaces.md` §"plugin-kiln/skills/kiln-metrics/SKILL.md (NEW)". Thin wrapper that invokes `orchestrator.sh`. `--help` describes the eight signals + column shape + log location + graceful-degrade. *(FR-015, FR-019)*
- [X] T035 [US4] Patch `plugin-kiln/.claude-plugin/plugin.json` to register the new `kiln-metrics` skill. Do NOT touch existing skill entries. *(plugin manifest registration; plan §Source Code structure)*

**Checkpoint**: All four themes shipped. SC-007, SC-008 verifiable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: PRD audit, smoke test, version bump, docs.

- [ ] T036 Run `/kiln:audit` (PRD compliance audit) per CLAUDE.md mandatory workflow §7: assert every PRD FR has a spec FR + implementation + test reference. Document any gap in `specs/vision-tooling/blockers.md` with a justification. *(constitution Article III + step 7 of mandatory workflow)*
- [ ] T037 Run `kiln:smoke-tester` agent on a fresh consumer-scaffold via `plugin-kiln/bin/init.mjs init` in a temp dir; verify `/kiln:kiln-roadmap --vision --add-constraint "smoke"` and `/kiln:kiln-metrics` both work end-to-end against the scaffolded structure. Confirm `.kiln/.vision.lock` and `.kiln/logs/metrics-*.md` paths are honoured by the consumer scaffold's `.gitignore` template. *(constitution Article V; step 9 of mandatory workflow)*
- [ ] T038 [P] Run `./scripts/version-bump.sh pr` to increment the PR segment of VERSION + sync to `plugin-kiln/package.json`. *(repo versioning convention)*
- [ ] T039 [P] Update `plugin-kiln/README.md` (or equivalent skill catalog doc) with a note describing the four new surfaces (`--add-*`/`--update-*`, `--check-vision-alignment`, opt-in forward-pass, `/kiln:kiln-metrics`). Include section-flag mapping table verbatim from `contracts/interfaces.md`. *(FR-021 maintenance contract surface)*
- [ ] T040 Run `/kiln:kiln-coverage` to verify NFR-004's ≥80% threshold against the assertion-block count convention. Document per-test PASS counts in `specs/vision-tooling/agent-notes/coverage-report.md`. *(NFR-004; PR #189 convention)*

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: T001 BLOCKS every later phase. T002–T004 are [P] and independent. Hard ordering: T001 first, T002–T004 in parallel after T001 (or alongside if no SKILL.md edits yet).
- **Phase 2 (Foundational)**: T005, T006 are [P] and depend only on T001. Both BLOCK every user story phase.
- **Phase 3 (US1, Theme A)**: depends on Phase 2. T007/T008 [P] alongside T009/T010 [P] (different files). T011 (SKILL.md edit) sequentially LAST in this phase.
- **Phase 4 (US2, Theme B)**: depends on Phase 2 + T011 (SKILL.md must already have simple-params dispatch in place; Theme B adds another mode in the same dispatch tree). T012/T013/T014 [P]; T015 depends on T013/T014; T016 sequentially after T011.
- **Phase 5 (US3, Theme C)**: depends on Phase 2 + T011 + T016 (forward-pass tail edits the same SKILL.md region as T011/T016). T017/T018/T019/T020/T021 [P]; T022 sequentially after T016.
- **Phase 6 (US4, Theme D)**: depends on Phase 2 only — fully independent of all other phases (kiln-metrics is a NEW skill in a new directory). T023–T032 all [P]; T033 depends on T024–T032; T034 depends on T033; T035 sequentially after T034.
- **Phase 7 (Polish)**: depends on completion of all desired user-story phases. T036 → T037 → T038/T039/T040 ([P] within Polish).

### User Story Dependencies

- **US1 (Theme A, P1)**: Foundation only. MVP — ships independently.
- **US2 (Theme B, P2)**: Foundation + Theme A's SKILL.md edit (T011) so the dispatch tree is in place.
- **US3 (Theme C, P2)**: Foundation + Theme A (T011) + Theme B (T016) — all three Theme paths cohabit `kiln-roadmap/SKILL.md`. Sequential edits.
- **US4 (Theme D, P3)**: Foundation only. New skill in new dir — no SKILL.md coupling. Fully independent of US1/US2/US3 — could ship even if US2/US3 slipped.

### Within Each User Story

- Tests authored in parallel with implementation (mock-LLM fixtures in particular MUST exist before LLM-mediated tasks can run). Tests do NOT have to fail-first since this is a propose-don't-apply pipeline; the `/implement` skill commits per phase.
- Helper scripts before SKILL.md integration tasks (writer + dispatch helpers exist before SKILL.md gets edited to call them).
- One commit per task (incremental task completion per Constitution Article VIII; mark `[X]` immediately on completion).

### Parallel Opportunities

- T002, T003, T004 in parallel after T001.
- T005, T006 in parallel after T001.
- T007, T008, T009, T010 all in parallel within Phase 3 (different files; T011 collects the work).
- T012, T013, T014 in parallel within Phase 4; T015 sequential after T013/T014.
- T017, T018, T019, T020, T021 all in parallel within Phase 5; T022 sequential.
- T023, T024, T025, T026, T027, T028, T029, T030, T031, T032 all in parallel within Phase 6 (eight extractors + renderer + test fixture, all different files).
- Phases 3, 4, 5, 6 can be parallelized across implementer agents IF SKILL.md sequencing (T011 → T016 → T022) is honoured — Theme D (Phase 6) is fully orthogonal and can run alongside any other phase.

---

## Parallel Example: Phase 6 (Theme D)

```bash
# Eight extractors + renderer + test fixture all parallel:
Task: "Implement plugin-kiln/scripts/metrics/render-row.sh"           # T024
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-a.sh"     # T025
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-b.sh"     # T026
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-c.sh"     # T027
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-d.sh"     # T028
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-e.sh"     # T029
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-f.sh"     # T030
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-g.sh"     # T031
Task: "Implement plugin-kiln/scripts/metrics/extract-signal-h.sh"     # T032
Task: "Author plugin-kiln/tests/kiln-metrics/run.sh"                  # T023
# orchestrator.sh + SKILL.md + plugin.json patch sequentially after.
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 Setup: T001 (CRITICAL ordering) → T002/T003/T004 in parallel.
2. Phase 2 Foundational: T005 + T006 in parallel.
3. Phase 3 US1: T007/T008/T009/T010 in parallel → T011 sequential.
4. **SELF-VALIDATE**: run `plugin-kiln/tests/vision-simple-params/run.sh` + `vision-coached-back-compat/run.sh`. SC-001/SC-002/SC-009 must pass.
5. Ship Theme A as MVP.

### Incremental Delivery

1. Setup + Foundational → ready for any user story.
2. US1 (Theme A) → ship MVP — closes "update friction" PRD goal.
3. US2 (Theme B) → ship — closes "drift visibility" PRD goal.
4. US3 (Theme C) → ship — closes "forward suggestion" PRD goal.
5. US4 (Theme D) → ship — closes "falsifiable scorecard" PRD goal.
6. Polish → audit + smoke + version-bump + docs.

### Parallel Team Strategy

- One implementer agent per Theme. Theme A blocks others on `kiln-roadmap/SKILL.md` edit (T011). Theme B + C share that file (T016, T022) and must serialize their SKILL.md edits. Theme D is fully orthogonal — could run alongside any phase.
- Recommend: Theme A implementer ships first (T001–T011), then Theme B + Theme C share an implementer (T012–T022, sequencing T016 after T011 and T022 after T016), and Theme D ships in parallel (T023–T035) by a second implementer.

---

## Notes

- Every implementation task references its FR(s) and the contract entry in `specs/vision-tooling/contracts/interfaces.md`. Function-signature drift requires updating the contract file FIRST (Constitution Article VII).
- Each task contains its file path. Mark `[X]` immediately on completion (Constitution Article VIII).
- Commit per phase boundary at minimum; per-task commits are encouraged for the audit trail.
- The 4-gate hook in `.claude/settings.json` allows edits to `plugin-kiln/` since this repo is the plugin source — but the gate still enforces spec+plan+tasks+`[X]` presence.
- LLM-mediated helpers (`vision-alignment-map.sh`, `vision-forward-pass.sh`) MUST honour `KILN_TEST_MOCK_LLM_DIR` per CLAUDE.md Rule 5; live-spawn validation of newly-shipped agents is an auditor follow-on.
