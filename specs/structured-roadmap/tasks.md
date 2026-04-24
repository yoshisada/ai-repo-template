---
description: "Task list for structured-roadmap feature — split between impl-roadmap and impl-integration"
---

# Tasks: Structured Roadmap Planning Layer

**Input**: `specs/structured-roadmap/spec.md` + `specs/structured-roadmap/plan.md` + `specs/structured-roadmap/contracts/interfaces.md`
**Source PRD**: `docs/features/2026-04-23-structured-roadmap/PRD.md`

**Tests**: REQUIRED — every user story has a test task. The `/kiln:kiln-test` harness (`plugin-skill` substrate) is the test runner.

**Organization**: Phase 1 (shared infra — owned by impl-roadmap) → Phase 2 (impl-roadmap user stories) and Phase 3 (impl-integration user stories) run in PARALLEL after Phase 1's helper-validators land → Phase 4 (cross-cutting polish) → Phase 5 (audit + smoke handed off to audit-compliance).

## Format: `[ID] [P?] [Story] [OWNER] Description`

- **[P]**: Can run in parallel within the same owner (different files, no dependencies).
- **[Story]**: Maps to spec.md user story (US1..US10) for traceability.
- **[OWNER]**: One of `impl-roadmap` or `impl-integration` (Phase 5 owner is `audit-compliance`).
- All implementation tasks must include the relevant FR comment in code per Constitution Article VII.

## Path Conventions

- Plugin source: `plugin-kiln/`, `plugin-shelf/`. No `src/` in this repo.
- Tests: `plugin-kiln/tests/structured-roadmap-<test-name>/` (per the `/kiln:kiln-test` harness convention).
- Helpers: `plugin-kiln/scripts/roadmap/*.sh` and `plugin-shelf/scripts/parse-roadmap-input.sh`.

---

## Phase 1: Shared Foundation (impl-roadmap)

**Purpose**: Schemas + validators + helpers that BOTH implementers depend on. Must complete before Phase 2/3 user-story work begins.

**⚠️ CRITICAL**: When T007 lands, impl-roadmap MUST SendMessage impl-integration: "Validators ready — distill extension is unblocked." Phase 3 cannot start until T007 is `[X]`.

- [X] T001 [impl-roadmap] Create directory `plugin-kiln/scripts/roadmap/` and stub all 10 helper scripts with shebang + usage comment matching `contracts/interfaces.md` §2 signatures (no behavior yet).
- [X] T002 [P] [impl-roadmap] Author `plugin-kiln/templates/vision-template.md` per spec FR-001 — short narrative starter with optional `last_updated:` frontmatter.
- [X] T003 [P] [impl-roadmap] Author `plugin-kiln/templates/roadmap-phase-template.md` per `contracts/interfaces.md` §1.2 (frontmatter + `## Items` body shape).
- [X] T004 [P] [impl-roadmap] Author `plugin-kiln/templates/roadmap-item-template.md` per `contracts/interfaces.md` §1.3 (full required + commented-optional frontmatter, body skeleton).
- [X] T005 [P] [impl-roadmap] Author `plugin-kiln/templates/roadmap-critique-template.md` per `contracts/interfaces.md` §1.3 critique branch (required `proof_path`).
- [X] T006 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/parse-item-frontmatter.sh` per §2.1 (jq-based YAML→JSON). FR-007.
- [X] T007 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` per §2.2 — INCLUDING enforcement of the §1.5 forbidden-fields list. FR-008. **🚦 unblocks impl-integration — SendMessage on completion.**
- [X] T008 [P] [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/validate-phase-frontmatter.sh` per §2.3. FR-005.
- [X] T009 [P] [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/list-items.sh` per §2.4 (filter by phase / kind / addresses / state, ASC sort). FR-009.

**Checkpoint**: shared validators + parsers ready. Both implementers can now consume.

---

## Phase 2: impl-roadmap user-story tasks

**Purpose**: Capture skill rewrite + interview + phase mgmt + migration + seed critiques.

### 2A — Lifecycle helpers

- [X] T010 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/update-item-state.sh` per §2.5 (atomic temp-write + mv, frontmatter-preserving). FR-021.
- [X] T011 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/update-phase-status.sh` per §2.6 (FR-020 single-in-progress guard + `--cascade-items` to flip planned → in-phase). FR-020, FR-021.
- [X] T012 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/migrate-legacy-roadmap.sh` per §2.7. FR-028. Idempotency guard: skip if `.kiln/roadmap.legacy.md` exists.
- [X] T013 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/seed-critiques.sh` per §2.8 — three pre-filled critique files with `proof_path`. FR-029.

### 2B — Classification + multi-item helpers

- [X] T014 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/classify-description.sh` per §2.9 + §4 (kind table) + §5 (cross-surface table). FR-014, FR-014a.
- [X] T015 [impl-roadmap] Implement `plugin-kiln/scripts/roadmap/detect-multi-item.sh` per §2.10. FR-018a.

### 2C — Skill rewrite (US1, US2, US3, US4, US6, US7, US8, US9, US10)

- [X] T016 [impl-roadmap] [US1, US4] Rewrite `plugin-kiln/skills/kiln-roadmap/SKILL.md` — skeleton (Step 0 first-run bootstrap → Step 1 cross-surface routing FR-014/FR-014b → Step 2 kind detection FR-014a → Step 3 multi-item prompt FR-018a/b). Calls helpers from T014/T015. The hand-off path MUST invoke target skills via the `Skill` tool (FR-014b, FR-036).
- [X] T017 [impl-roadmap] [US1] Add Step 4 "Adversarial interview" to the SKILL.md — implements §6.1 question bank for `feature` + §6.7 sizing questions; ≤5 questions, individually skippable. FR-015, FR-017.
- [X] T018 [impl-roadmap] [US2] Add §6.2 critique-specific interview branch to SKILL.md, including REQUIRED `proof_path` re-prompt loop. FR-011, FR-015.
- [X] T019 [impl-roadmap] [US1, US2] Add §6.3–§6.6 interview branches (research / goal / constraint / non-goal / milestone) to SKILL.md. FR-015.
- [X] T020 [impl-roadmap] [US1] Add Step 5 "Write item file" — composes frontmatter per §1.3, runs `validate-item-frontmatter.sh` BEFORE write, calls `shelf:shelf-write-roadmap-note` workflow for Obsidian mirror. FR-007, FR-030, FR-037.
- [X] T021 [impl-roadmap] [US1] Add Step 6 "Update phase file" — appends item-id to `phases/<phase>.md` `## Items` list via `update-phase-status.sh` (no status change, just item registration). FR-006.
- [X] T022 [impl-roadmap] [US3] Add `--quick` flag handling — bypasses Steps 4–6 interview, writes minimal item to `phase: unsorted`, suppresses follow-up loop. Auto-detect non-interactive shell. FR-018.
- [X] T023 [impl-roadmap] [US7] Add `--phase start | complete | create` subcommand. Calls `update-phase-status.sh`. Refuses concurrent `in-progress`. FR-020.
- [X] T024 [impl-roadmap] [US6] Add `--vision` subcommand — show current `.kiln/vision.md`, run short interview, write update, dispatch shelf workflow with `obsidian_subpath: vision.md` for `patch_file` mirror. FR-019, FR-031.
- [X] T025 [impl-roadmap] Add `--check` subcommand — runs `list-items.sh` + cross-references with phase status / spec / PR existence; reports inconsistencies. FR-022.
- [X] T026 [impl-roadmap] Add `--reclassify` subcommand — walks all `phase: unsorted` items through the interview to promote them to a real phase + kind. FR-028 follow-up.
- [X] T027 [impl-roadmap] [US10] Add Step 7 "Follow-up loop" — after each successful capture, ask "anything else on your mind?"; loop back through Step 1 routing. Skip on `--quick` / non-interactive. Exit on `no` / empty. Print per-surface session summary. FR-018c, FR-039.
- [X] T028 [impl-roadmap] [US8] First-run bootstrap (Step 0 of SKILL.md): create `.kiln/vision.md` + `.kiln/roadmap/{phases,items}/`, run `migrate-legacy-roadmap.sh`, run `seed-critiques.sh`, print summary. FR-001, FR-002, FR-028, FR-029.
- [X] T029 [impl-roadmap] [FR-040] When `.shelf-config` is missing or partial, print one-line warning + continue with `.kiln/` writes only. Skill MUST NOT fail.

### 2D — Tests (impl-roadmap side)

- [ ] T030 [P] [impl-roadmap] [US1] Author `plugin-kiln/tests/structured-roadmap-capture-feature/` (skill test fixture + expected-output assertions). Test = US1 acceptance scenarios 1–3.
- [ ] T031 [P] [impl-roadmap] [US2] Author `plugin-kiln/tests/structured-roadmap-capture-critique/` — asserts `kind: critique`, `proof_path` required, `status: open`. Test = US2 acceptance scenarios 1, 3.
- [ ] T032 [P] [impl-roadmap] [US3] Author `plugin-kiln/tests/structured-roadmap-quick-path/` — asserts no interview, `phase: unsorted`, no follow-up prompt. Test = US3 acceptance scenarios 1–3.
- [ ] T033 [P] [impl-roadmap] [US4] Author `plugin-kiln/tests/structured-roadmap-cross-surface-routing/` — asserts routing prompt shown for tactical input AND that picking `(b)` invokes `/kiln:kiln-report-issue` via Skill tool (FR-036). Test = US4 acceptance scenarios 1, 2.
- [ ] T034 [P] [impl-roadmap] [US7] Author `plugin-kiln/tests/structured-roadmap-phase-mgmt/` — asserts single-in-progress refusal + cascade item state. Test = US7 acceptance scenarios 1, 2.
- [ ] T035 [P] [impl-roadmap] [US8] Author `plugin-kiln/tests/structured-roadmap-migration-legacy/` — fixture has 3 bullets in `.kiln/roadmap.md`; assert 3 item files + `.kiln/roadmap.legacy.md` + idempotency on re-run. Test = US8 acceptance scenarios 1, 2.
- [ ] T036 [P] [impl-roadmap] Author `plugin-kiln/tests/structured-roadmap-seed-critiques/` — asserts three seed files appear ONLY when items dir empty. FR-029.
- [ ] T037 [P] [impl-roadmap] Author `plugin-kiln/tests/structured-roadmap-validator-rejects-forbidden/` — fixture items containing `human_time`, `t_shirt_size`, `effort_days`; assert validator returns `ok: false` for each. FR-008, SC-006.
- [ ] T038 [P] [impl-roadmap] [US9] Author `plugin-kiln/tests/structured-roadmap-multi-item/` — input with "and also" yields 2 item files with shared phase. FR-018a, FR-018b.
- [ ] T039 [P] [impl-roadmap] [US10] Author `plugin-kiln/tests/structured-roadmap-followup-loop/` — answer "yes" to follow-up with tactical description, assert `/kiln:kiln-report-issue` invocation + final session summary. FR-018c, FR-039.

**Checkpoint**: capture flow + interview + lifecycle + migration + tests all green. impl-roadmap scope complete.

---

## Phase 3: impl-integration user-story tasks

**Purpose**: distill extension + shelf workflow + next + specify hooks. Runs in PARALLEL with Phase 2 once T007 lands.

### 3A — Shelf workflow + helper

- [X] T040 [impl-integration] Implement `plugin-shelf/scripts/parse-roadmap-input.sh` per §2.11 — parses skill output into the agent-step input JSON with `obsidian_subpath`. FR-035.
- [X] T041 [impl-integration] Author `plugin-shelf/workflows/shelf-write-roadmap-note.json` per §3 — 4 steps, MCP scope locked to `create_file` + `patch_file`, decision rule per §3.2, action selection per §3.3, finalize-result JSON per §3.4. Mirrors `shelf-write-issue-note.json`. FR-030, FR-035.
- [ ] T042 [P] [impl-integration] Author `plugin-kiln/tests/structured-roadmap-shelf-mirror-paths/` — fixtures with full `.shelf-config` and partial `.shelf-config`; assert `path_source` literal strings + `obsidian_path` shape per §3.2. FR-004.

### 3B — Distill extension (US5)

- [X] T043 [impl-integration] [US5] Modify `plugin-kiln/skills/kiln-distill/SKILL.md` Step 1 — add items glob + filter pipeline. Items get `type_tag: item`. FR-023.
- [X] T044 [impl-integration] [US5] Modify Step 2 grouping — three-section ordering: feedback themes → item-led themes → issue-only themes; sort within group ASC by filename. FR-024, contract §7.2.
- [X] T045 [impl-integration] [US5] Add `--phase`, `--addresses`, `--kind` filter parsing per §7.3. Default `--phase current` resolves to the one phase with `status: in-progress`. FR-025.
- [X] T046 [impl-integration] [US5] Modify Step 4 PRD frontmatter emission — `derived_from:` includes items, sorted feedback → items → issues per §7.2. NFR-determinism preserved. FR-024, FR-026.
- [X] T047 [impl-integration] [US5] Modify Step 4 PRD body — `## Background` para 2 cites recent items; new `## Implementation Hints` section renders `implementation_hints:` from items with item-id back-references. FR-027.
- [X] T048 [impl-integration] [US5] Modify Step 5 status update — for each selected item, call `update-item-state.sh <path> distilled` and patch `prd:` field. Roll back on failure. FR-026, contract §7.5.

### 3C — `/kiln:kiln-next` extension

- [X] T049 [impl-integration] Modify `plugin-kiln/skills/kiln-next/SKILL.md` — append "Active phase items" section calling `list-items.sh --state in-phase`. Empty when no phase is in-progress. Contract §8. FR-033.

### 3D — `/kiln:kiln-specify` (or `/specify`) hook

- [X] T050 [impl-integration] Modify `plugin-kiln/skills/kiln-specify/SKILL.md` — after `spec.md` write, scan PRD frontmatter `derived_from:` for `.kiln/roadmap/items/` paths; for each, call `update-item-state.sh <path> specced` + patch `spec:` field. No-op when no roadmap items referenced. Contract §9. FR-034.

### 3E — Tests (impl-integration side)

- [ ] T051 [P] [impl-integration] [US5] Author `plugin-kiln/tests/structured-roadmap-distill-three-streams/` — fixture with 1 feedback + 1 item + 1 issue all matching current phase; assert PRD `derived_from:` contains all three in §7.2 order, item state → distilled. Test = US5 acceptance scenarios 1, 3.
- [ ] T052 [P] [impl-integration] [US5] Author `plugin-kiln/tests/structured-roadmap-distill-addresses-filter/` — fixture with critique + 2 items addressing it + 1 unrelated item; assert only the 2 addressing items are bundled. FR-025.
- [ ] T053 [P] [impl-integration] [US5] Author `plugin-kiln/tests/structured-roadmap-distill-kind-filter/` — `--kind research` only bundles research items. FR-025.
- [ ] T054 [P] [impl-integration] [US5] Author `plugin-kiln/tests/structured-roadmap-distill-implementation-hints/` — item with `implementation_hints` produces a PRD with `## Implementation Hints` section + back-reference. FR-027.
- [ ] T055 [P] [impl-integration] Author `plugin-kiln/tests/structured-roadmap-next-surfaces-in-phase/` — fixture with one in-phase item; assert `/kiln:kiln-next` output includes "Active phase items" section with the item. FR-033.
- [ ] T056 [P] [impl-integration] Author `plugin-kiln/tests/structured-roadmap-specify-state-hook/` — fixture PRD with `derived_from:` referencing one item; run specify; assert item state → specced + `spec:` field set. FR-034.

**Checkpoint**: distill bundles all three streams, shelf workflow mirrors all roadmap files, next + specify wired into lifecycle.

---

## Phase 4: Cross-cutting polish (impl-roadmap + impl-integration coordinate)

- [ ] T057 [P] [impl-roadmap] Add FR-comment line to every helper / skill section (e.g., `# FR-008 / PRD FR-008: AI-native sizing only`) — Constitution Article VII. Audit-compliance gates this.
- [ ] T058 [P] [impl-integration] Same FR-comment audit for distill / next / specify / shelf-write-roadmap-note touchpoints.
- [ ] T059 [impl-roadmap] Update `plugin-kiln/.claude-plugin/plugin.json` skill descriptor for `kiln-roadmap` (description text changes — no longer "Append items to .kiln/roadmap.md").
- [ ] T060 [impl-integration] Update `plugin-kiln/.claude-plugin/plugin.json` skill descriptor for `kiln-distill` (description mentions third stream + new filters).
- [ ] T061 [impl-roadmap] Update top-level `CLAUDE.md` "Available Commands" → describe new `/kiln:kiln-roadmap` flags + behavior; document `shelf:shelf-write-roadmap-note`.
- [ ] T062 [impl-integration] Update `CLAUDE.md` `/kiln:kiln-distill` entry — list new filters.
- [ ] T063 [impl-roadmap] Verify ALL helpers + tests under `plugin-kiln/scripts/roadmap/` pass `bashcov` ≥80% line + branch coverage. Constitution Article II.

---

## Phase 5: Audit + Smoke (audit-compliance owns)

- [ ] T064 [audit-compliance] Run `kiln:audit` against this spec. Verify every PRD FR-001..FR-031 maps to a spec FR (already done in spec §FR-IDs) AND every spec FR-IDs maps to ≥1 task above. Document any gaps in `specs/structured-roadmap/blockers.md`.
- [ ] T065 [audit-compliance] Verify upstream blocker `2026-04-23-write-issue-note-ignores-shelf-config` is closed. If not, write blocker entry — PR cannot proceed.
- [ ] T066 [audit-compliance] Run smoke-tester agent — scaffold temp consumer project, exercise full flow (capture feature → capture critique → quick path → cross-surface routing → distill three-stream → specify hook → next surfaces in-phase items). Record outcomes.
- [ ] T067 [audit-compliance] Run `/kiln:kiln-test plugin-kiln` to execute every test under `plugin-kiln/tests/structured-roadmap-*/`. All must pass.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** (Shared Foundation): No blockers. Owned by impl-roadmap. Must complete T007 before Phase 3 starts.
- **Phase 2** (impl-roadmap stories): Depends on Phase 1 T001–T009.
- **Phase 3** (impl-integration stories): Depends on Phase 1 T007 only (validators). Runs PARALLEL to Phase 2.
- **Phase 4** (Polish): Depends on Phase 2 + Phase 3 complete.
- **Phase 5** (Audit + Smoke): Depends on Phase 4.

### Within each implementer's scope

- impl-roadmap runs T010–T015 before T016 (skill rewrite needs the helpers).
- impl-roadmap runs T016 (skeleton) before T017–T028 (per-flag handlers).
- impl-roadmap runs T020 BEFORE T030–T039 tests.
- impl-integration runs T040 + T041 before T043–T048 (distill needs the workflow to call into for item writes during state updates? — NO; distill writes state via `update-item-state.sh` directly, not through shelf. Order is purely for shelf-mirror tests T042 to be testable.).
- impl-integration runs T043–T048 in order (each step builds on the last).

### Parallel opportunities (within an implementer)

- T002 / T003 / T004 / T005 — all template authoring (no shared file).
- T008 / T009 — different validator files.
- T030–T039 tests are all independent fixtures.
- T051–T056 tests are all independent fixtures.
- T057 + T058 polish tasks are independent.

### Cross-implementer coordination

- T007 completion → SendMessage impl-integration.
- T020 completion (item-write calls into shelf workflow) → coordinate with impl-integration on T041 — the workflow must exist before T020 can be tested end-to-end. Suggested order: impl-integration completes T041 EARLY (block on T040 only), then notifies impl-roadmap.

---

## Implementation Strategy

### MVP First (US1 — capture a feature)

1. Phase 1 T001–T009 (shared validators).
2. Phase 2 T010–T011 (lifecycle helpers).
3. Phase 3 T040–T041 (shelf workflow).
4. Phase 2 T016 + T017 + T020 + T021 (capture-feature happy path).
5. Phase 2 T030 (US1 test).

This delivers US1 fully working — adversarial-interview feature capture with Obsidian mirror — and is the smallest reviewable slice.

### Incremental Delivery

1. MVP (US1) → review.
2. + US2 (critique) + US4 (cross-surface routing) — the highest-value adjacent stories.
3. + US3 (quick path) + US10 (follow-up loop) — usability layer.
4. + US5 (distill extension) — closes the loop.
5. + US6/US7/US8/US9 (vision / phase mgmt / migration / multi-item) — completeness.

### Parallel Team Strategy

- impl-roadmap: Phase 2 — capture skill scope.
- impl-integration: Phase 3 — distill + shelf + next + specify scope.
- They coordinate via SendMessage on T007 (validators ready) and T041 (shelf workflow ready). No file-overlap between their scopes.

---

## Notes

- Every `[X]`-mark MUST be made immediately on task completion (Article VIII). No batched marking.
- Commit after each phase: end of Phase 1, end of each user-story group within Phase 2/3, end of Phase 4.
- Tests for a user story MUST be authored alongside the implementation, not deferred.
- Any contract change requires updating `contracts/interfaces.md` FIRST, then SendMessage to BOTH implementers + team-lead.
- The PR must reference both the spec (this directory) and the source PRD.
