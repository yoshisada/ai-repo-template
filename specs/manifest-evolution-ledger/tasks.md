---
description: "Task list for manifest-evolution-ledger feature implementation"
---

# Tasks: Manifest-Evolution Ledger — V1 Pure-History View

**Input**: `specs/manifest-evolution-ledger/spec.md`, `specs/manifest-evolution-ledger/plan.md`, `specs/manifest-evolution-ledger/contracts/interfaces.md`
**Prerequisites**: spec.md (FR-001..FR-007, NFR-001..NFR-005, SC-001..SC-006), plan.md, contracts/interfaces.md.

## Format: `[ID] [Story] Description`

- **[Story]**: Maps to spec user story (US1..US3) or cross-cutting (CC) for back-compat / linking / extensibility checks.
- File paths are exact and absolute under repo root.

## Implementer Assignment

- **`implementer`** owns Phases 1, 3, 4, 5, 6, 7. All edits land in NEW paths (no concurrent-staging hazard).

---

## Phase 1: Setup (implementer)

**Purpose**: Confirm working tree is clean and the constitution + spec + contracts are read. No code edits yet.

- [ ] T001 [implementer] Read `.specify/memory/constitution.md`, `specs/manifest-evolution-ledger/spec.md`, `specs/manifest-evolution-ledger/plan.md`, `specs/manifest-evolution-ledger/contracts/interfaces.md` end-to-end before any edit.
- [ ] T002 [implementer] Verify `git status` is clean on `build/manifest-evolution-ledger-20260427` after the artifact-commit lands. If dirty, stash before starting code work.
- [ ] T003 [implementer] Confirm `plugin-kiln/skills/kiln-ledger/`, `plugin-kiln/scripts/ledger/`, and `plugin-kiln/tests/ledger-*` directories do NOT exist yet (skill is fresh; SC-004 additivity).

---

## Phase 3: User Story 1 — Chronological view (P1) 🎯 MVP — implementer

**Goal**: Three readers + renderer + orchestrator produce a non-empty 6-row timeline against a fixture corpus.
**Independent Test**: `plugin-kiln/tests/ledger-chronological-emission/run.sh` returns PASS.

### Implementation — Readers (FR-001, FR-006)

- [ ] T010 [implementer] [US1] Create `plugin-kiln/scripts/ledger/read-mistakes.sh` per `contracts/interfaces.md` §A.1. Parse `--since` + `--root`; emit one NDJSON row per `.kiln/mistakes/*.md`; date from filename prefix with mtime fallback; summary = first non-frontmatter non-blank line ≤120ch. Add `# FR-001 # FR-006` header comment.
- [ ] T011 [implementer] [US1] Create `plugin-kiln/scripts/ledger/read-proposals.sh` per `contracts/interfaces.md` §A.2. Shell out to existing shelf MCP shim; honor `MCP_SHELF_DISABLED=1` env (exit 4); emit NDJSON rows for both `@inbox/open/` and `@inbox/applied/`. Resolution-link populated for `proposal-applied` only. Add `# FR-001 # FR-006` header comment.
- [ ] T012 [implementer] [US1] Create `plugin-kiln/scripts/ledger/read-edits.sh` per `contracts/interfaces.md` §A.3. Declare `MANIFEST_EDIT_PATTERNS` array constant at the top with the FR-007 four-pattern initial set. Run `git log --since "$SINCE" --grep=...` (multi-grep OR-combine); emit ONE row per commit (OQ-2); summary = `<subject> (+<N> manifest files)`; resolution = first `applies inbox/...` body match. Add `# FR-001 # FR-006 # FR-007` header comment AND a maintenance-contract comment block citing FR-007.

### Implementation — Renderer (FR-002, NFR-001, NFR-002)

- [ ] T013 [implementer] [US1] Create `plugin-kiln/scripts/ledger/render-timeline.sh` per `contracts/interfaces.md` §B.1. Read NDJSON from stdin; parse `--substrates / --reason / --since` argv; sort under `LC_ALL=C` by `(date DESC, source ASC)` with stable tiebreak; emit H1 with ISO-8601 timestamp, optional NFR-002 banner, `## Events` markdown table, `## Notes` section with missing-link aggregate + fallback notes + empty-corpus message. Add `# FR-002 # NFR-001 # NFR-002` header comment.

### Implementation — Orchestrator (FR-001, FR-003, FR-004, FR-005)

- [ ] T014 [implementer] [US1] Create `plugin-kiln/skills/kiln-ledger/SKILL.md` per `contracts/interfaces.md` §C.1. YAML frontmatter `name: kiln-ledger` + description. Body contains the flag-parsing block (FR-003), reader-dispatch with degradation catch (FR-001 / FR-005), `--type` post-aggregation `jq` filter, and the `tee` write to `.kiln/logs/ledger-<ts>.md` (FR-004).
- [ ] T015 [implementer] [US1] Verify the orchestrator emits malformed-flag errors to stderr with exit 1 (FR-005 carve-out): unknown flag, malformed `--since`, invalid `--type`, invalid `--substrate` token. Add `# FR-005` comment on each validate branch.

### Test for User Story 1

- [ ] T016 [implementer] [US1] Create `plugin-kiln/tests/ledger-chronological-emission/run.sh` per `contracts/interfaces.md` §D.1. Header comment cites SC-001 + NFR-001. Scaffold 2 mistakes + 2 stubbed proposals + 2 commits matching `MANIFEST_EDIT_PATTERNS` in a temp git repo. Stub MCP shim under `$TMP/bin`. Invoke the orchestrator. Assertions (≥4 distinct `assert_*` per NFR-004 proxy): (a) 6 rows in `## Events`, (b) date-descending order, (c) `.kiln/logs/ledger-<ts>.md` exists, (d) stdout byte-identical to log file, (e) re-run produces byte-identical output below H1 timestamp.
- [ ] T017 [implementer] [US1] Run `bash plugin-kiln/tests/ledger-chronological-emission/run.sh` locally; assert PASS.

**Checkpoint**: Phase 3 ends with US1 fully shippable. Commit before moving to Phase 4.

- [ ] T018 [implementer] Commit Phase 3 with message `feat(kiln-ledger): readers + renderer + orchestrator MVP (FR-001..FR-007, NFR-001..NFR-002)`.

---

## Phase 4: User Story 2 — Filter shape (P1) — implementer

**Goal**: `--type` and `--since` filters AND-combine; malformed values exit 1.
**Independent Test**: `plugin-kiln/tests/ledger-filter-shape/run.sh` returns PASS.

### Implementation

- [ ] T020 [implementer] [US2] Verify the orchestrator's post-aggregation `jq` filter (T014) handles all four `--type` values (`mistake`, `proposal`, `edit`, `all`) AND treats `--type proposal` as matching BOTH `proposal-open` AND `proposal-applied` (FR-003 vocabulary alignment). Add inline comment citing FR-003.
- [ ] T021 [implementer] [US2] Verify the readers honor `--since` correctly (each reader filters at-source so the orchestrator doesn't aggregate excluded events into NDJSON). Cross-check by running each reader standalone with `--since 2030-01-01` against the SC-001 corpus — expect zero rows.

### Test for User Story 2

- [ ] T022 [implementer] [US2] Create `plugin-kiln/tests/ledger-filter-shape/run.sh` per `contracts/interfaces.md` §D.2. Header cites SC-002. Reuses the SC-001 corpus. Assertions (≥4): (a) `--type edit --since 2026-04-20` emits ONLY `edit` rows where `date >= 2026-04-20`, (b) `--type mistake --since 2030-01-01` emits zero rows, (c) `--substrate mistakes,edits` skips proposals entirely, (d) malformed `--type banana` → exit 1 with stderr error.
- [ ] T023 [implementer] [US2] Run fixture; assert PASS.

**Checkpoint**: Phase 4 ends with US2 fully shippable.

- [ ] T024 [implementer] Commit Phase 4 with message `test(kiln-ledger): filter shape AND-combined (FR-003, SC-002)`.

---

## Phase 5: User Story 3 — Degraded substrate (P2) — implementer

**Goal**: Auto-degrade on shelf MCP failure + explicit `--substrate` opt-out both surface the NFR-002 banner and exit 0.
**Independent Test**: `plugin-kiln/tests/ledger-degraded-substrate/run.sh` returns PASS.

### Implementation

- [ ] T030 [implementer] [US3] Verify `read-proposals.sh` exits 4 immediately when `MCP_SHELF_DISABLED=1` is set (FR-005 SC-003 path). No MCP call attempted. Add `# FR-005` comment on the env-check branch.
- [ ] T031 [implementer] [US3] Verify the orchestrator's degraded-substrate catch (T014) appends the verbatim reasons listed in NFR-002 (`shelf unavailable, proposals omitted | proposals opted-out via --substrate | mistakes opted-out via --substrate | edits opted-out via --substrate`). Multi-omission joins with `; `. Reason text MUST match the NFR-002 contract byte-for-byte.

### Test for User Story 3

- [ ] T032 [implementer] [US3] Create `plugin-kiln/tests/ledger-degraded-substrate/run.sh` per `contracts/interfaces.md` §D.3. Header cites SC-003. Two scenarios: (1) `MCP_SHELF_DISABLED=1` with default `--substrate all`; (2) explicit `--substrate mistakes,edits`. Assertions (≥4): (a) exit 0 in both scenarios, (b) banner contains `shelf unavailable, proposals omitted` in scenario 1, (c) banner contains `proposals opted-out via --substrate` in scenario 2, (d) no `proposal-*` rows in either, (e) `mistake` and `edit` rows render normally.
- [ ] T033 [implementer] [US3] Run fixture; assert PASS.

**Checkpoint**: Phase 5 ends with US3 fully shippable.

- [ ] T034 [implementer] Commit Phase 5 with message `test(kiln-ledger): degraded substrate banner + auto-degrade (FR-005, NFR-002, SC-003)`.

---

## Phase 6: Cross-cutting — back-compat + linking + extensibility (CC) — implementer

**Goal**: SC-004 (back-compat additivity), SC-005 (proposal-edit linking), SC-006 (orchestrator-reader split survives reader-add).
**Independent Tests**: three fixtures must each return PASS.

### Implementation (mostly already covered by T012 + T013; verify)

- [ ] T040 [implementer] [CC] Verify `read-edits.sh` populates `resolution` field with the parsed `applies inbox/(open|applied)/<path>` token from the commit body when present, empty string when absent (SC-005). Cross-check with the `read-proposals.sh` resolution-population path so `proposal-applied` rows back-link to commits AND `edit` rows back-link to proposals (bi-directional).
- [ ] T041 [implementer] [CC] Verify `render-timeline.sh` Notes section emits the missing-link aggregate `<K> edits found, <J> lacked proposal back-references` ONLY when at least one `edit` row has empty resolution (SC-005, R-1).

### Tests

- [ ] T042 [implementer] [CC] Create `plugin-kiln/tests/ledger-back-compat/run.sh` per `contracts/interfaces.md` §D.4. Header cites SC-004. Assertions (≥4): (a) all new files under `plugin-kiln/skills/kiln-ledger/` OR `plugin-kiln/scripts/ledger/` OR `plugin-kiln/tests/ledger-*/`, (b) zero edits to existing skills, (c) zero edits to existing scripts, (d) zero edits to existing tests. Implementation: `git diff --name-only origin/main...HEAD` filtered against the allow-list.
- [ ] T043 [implementer] [CC] Create `plugin-kiln/tests/ledger-proposal-edit-linking/run.sh` per `contracts/interfaces.md` §D.5. Header cites SC-005. Scaffolds one proposal `@inbox/applied/2026-04-15-foo.md` + one commit body referencing it + one edit commit WITHOUT a back-ref. Assertions (≥4): (a) `proposal-applied` row's resolution contains the commit hash, (b) linked `edit` row's resolution contains the proposal path, (c) unlinked `edit` row's resolution is `—`, (d) Notes section reports `<K> edits found, <J> lacked proposal back-references` with K=2 J=1.
- [ ] T044 [implementer] [CC] Create `plugin-kiln/tests/ledger-orchestrator-reader-split/run.sh` per `contracts/interfaces.md` §D.6. Header cites SC-006. Programmatically scaffold a hypothetical `read-feedback-resolutions.sh` stub. Assertions (≥4): (a) only the new reader file appears under `plugin-kiln/scripts/ledger/`, (b) the orchestrator SKILL.md change is one substrate-list line, (c) a new test fixture is added, (d) `render-timeline.sh` is byte-identical pre/post (compute SHA-256, compare).
- [ ] T045 [implementer] [CC] Run all three fixtures; assert PASS for each.

**Checkpoint**: Phase 6 ends with all six SCs covered.

- [ ] T046 [implementer] Commit Phase 6 with message `test(kiln-ledger): back-compat + linking + extensibility (SC-004..SC-006)`.

---

## Phase 7: Polish & cross-cutting

- [ ] T050 [implementer] Confirm `plugin-kiln/skills/kiln-ledger/SKILL.md` total length stays under 500 lines (constitution Article VI). Largest expected: ~250 lines.
- [ ] T051 [implementer] Confirm each new shell script has executable permissions and a shebang `#!/usr/bin/env bash` line.
- [ ] T052 [implementer] Manual smoke against this repo: `bash plugin-kiln/skills/kiln-ledger/SKILL.md --since 2026-04-01` (or equivalent skill-invoke pattern). Record observed wall-clock + row count + any fallback Notes lines in `agent-notes/implementer.md`. (No hard latency budget — V1 budget per OQ-3 is "<30s".)
- [ ] T053 [implementer] Write `specs/manifest-evolution-ledger/agent-notes/implementer.md` with friction notes (any unclear contract, blockers encountered, prompt-improvement proposals using bold-inline `**PI-N**` format). Required deliverable per FR-009 of build-prd.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no deps. Starts immediately.
- **Phase 3 (US1)**: depends on Phase 1. Sequential (readers → renderer → orchestrator → fixture).
- **Phase 4 (US2)**: depends on Phase 3. Reuses the orchestrator + corpus from US1.
- **Phase 5 (US3)**: depends on Phase 4 (no functional dep, but commit ordering).
- **Phase 6 (CC)**: depends on Phase 5 (all functional code in place; CC tests verify properties).
- **Phase 7 (Polish)**: depends on Phase 6.

### Within Each User Story

- Implementation tasks before test-fixture tasks within the same phase (the fixture asserts the implementation).
- Commit after each phase (T018, T024, T034, T046).
- Friction notes (T053) before the implementer signals completion to team-lead.

### No Parallel Opportunities

Single implementer; phases are sequential. The reader scripts (T010 / T011 / T012) could in principle run in parallel sub-tasks but the task overhead exceeds the benefit for V1.

---

## Implementation Strategy

### MVP First (US1 — chronological view)

1. Phase 1 (read-only setup).
2. Phase 3 — readers → renderer → orchestrator → SC-001 fixture. This IS the MVP; everything else is incremental quality.
3. Phase 4 (US2 — filter shape): tightens contract.
4. Phase 5 (US3 — degraded substrate): hardens against MCP unavailability.
5. Phase 6 (CC): proves additivity, linking, extensibility.
6. Phase 7: polish + smoke + friction notes.

---

## Notes

- All edits land in NEW paths — no concurrent-staging hazard.
- [Story] label maps task to spec user story or `CC` for cross-cutting.
- Each user story (US1..US3) is independently completable and testable.
- `run.sh`-only fixture pattern per NFR-004 (substrate gap B-1 carve-out). Run via direct `bash <path>/run.sh`; do NOT downgrade to `test.yaml`.
- Verify fixtures fail before implementation (TDD-lite); add the impl, re-verify they PASS.
- Commit after each phase; do not batch.
- Friction notes are part of the deliverable, not optional (FR-009 of build-prd).
- Total task count: 27 (well under the 20-task threshold for spawning a second implementer — single implementer is appropriate).
