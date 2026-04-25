---
description: "Task list for workflow-governance feature implementation"
---

# Tasks: Workflow Governance

**Input**: Design documents from `specs/workflow-governance/`
**Prerequisites**: spec.md ✅, plan.md ✅, contracts/interfaces.md ✅

## Format: `[ID] [P?] [Owner] Description`

- **[P]**: Can run in parallel (different files, no dependencies within the same phase)
- **[Owner]**: Which implementer owns the task
  - `[impl-governance]` — hook fixture + roadmap `--promote` + distill gate (FR-001..FR-008)
  - `[impl-pi-apply]` — `/kiln:kiln-pi-apply` skill + helpers + `/kiln:kiln-next` integration (FR-009..FR-013)
- Every task includes exact file paths.
- Every implementation task references its FR(s) for traceability.

Tracks A (impl-governance) and B (impl-pi-apply) can run concurrently. Track A's Phase 1 is independent of its own Phase 2/3. Within Track A, Phase 2 (`--promote`) must land before Phase 3 (distill gate consumes the escape hatch).

---

## Phase 1 — Hook Verification Fixture (impl-governance)

**Blocks**: Nothing (independent release per NFR-004).

**Goal**: Lock the already-shipped `build/*` accept-list entry in `require-feature-branch.sh` with a regression fixture. No hook source edit.

### Tests (this phase IS the test — the hook is already implemented)

- [X] **T001** `[impl-governance]` Create fixture directory `plugin-kiln/tests/require-feature-branch-build-prefix/` with `fixture/`, `expected/`, and `run.sh`.
- [X] **T002** `[P]` `[impl-governance]` Author `plugin-kiln/tests/require-feature-branch-build-prefix/run.sh` with the 5 test cases from `contracts/interfaces.md` Module 4 (positive `build/*`, negative `main`, negative `feature/foo`, negative random, performance guard). **Validates**: FR-001, FR-002, FR-003, NFR-001.
- [X] **T003** `[P]` `[impl-governance]` Author fixture git state under `plugin-kiln/tests/require-feature-branch-build-prefix/fixture/` — minimal `.git/` with pre-seeded branches `build/workflow-governance-20260424`, `main`, `feature/foo`, `randomstring`, and a `.specify/memory/constitution.md` stub so the hook's other gates pass. **Implementation note**: `run.sh` creates a disposable `mktemp -d` git repo on each invocation (portable across macOS/Linux; no pre-committed `.git/` blob to maintain). FR-003 requirement of "simulated branches" is satisfied by `git branch <name>` calls inside `run.sh`.
- [X] **T004** `[impl-governance]` Capture baseline hook runtime (median of 10 runs, positive case only) and store at `plugin-kiln/tests/require-feature-branch-build-prefix/fixture/baseline-ms.txt`. **Validates**: NFR-001.
- [X] **T005** `[impl-governance]` Run the fixture and assert all 5 cases pass. Invoked directly via `bash plugin-kiln/tests/require-feature-branch-build-prefix/run.sh` (harness-type `static` — the `/kiln:kiln-test` harness v1 only wires `plugin-skill`, so direct bash invocation is the working path). Commit Phase 1 with message `test(workflow-governance): add require-feature-branch-build-prefix fixture (FR-003)`.

**Checkpoint**: Hook regression boundary locked. Track A continues to Phase 2.

---

## Phase 2 — Roadmap `--promote` Path (impl-governance)

**Depends on**: Nothing upstream (Phase 1 independent). Blocks Phase 3 within this track.

**Goal**: Implement `/kiln:kiln-roadmap --promote <source>` as a first-class escape hatch so the distill gate (Phase 3) is non-punitive.

### Tests (write FIRST, ensure they FAIL before implementation)

- [X] **T006** `[impl-governance]` Create fixture `plugin-kiln/tests/roadmap-promote-basic/` — happy path: `.kiln/issues/2026-04-24-widget-dark-mode.md` (body ≥ 200 chars, `status: open`), run `/kiln:kiln-roadmap --promote <path>` with coached accept-all, assert new item file exists with required frontmatter and source is `status: promoted` + `roadmap_item:`. **Validates**: FR-006, SC-003.
- [X] **T007** `[P]` `[impl-governance]` Create fixture `plugin-kiln/tests/roadmap-promote-byte-preserve/` — capture `sha256sum` of the source body (bytes after closing `---`) before promotion and after, assert identical. **Validates**: NFR-003.
- [X] **T008** `[P]` `[impl-governance]` Create fixture `plugin-kiln/tests/roadmap-promote-idempotency/` — pre-seed source with `status: promoted`, run `/kiln:kiln-roadmap --promote <path>`, assert exit code 5 and clear "already promoted" message. **Validates**: FR-006 (Acceptance Scenario 5).
- [X] **T009** `[P]` `[impl-governance]` Create fixture `plugin-kiln/tests/roadmap-promote-missing-source/` — run `/kiln:kiln-roadmap --promote .kiln/issues/does-not-exist.md`, assert exit code 3. **Validates**: FR-006 (Acceptance Scenario 6).

### Implementation

- [X] **T010** `[impl-governance]` Implement `plugin-kiln/scripts/roadmap/promote-source.sh` per `contracts/interfaces.md` Module 2. MUST set `LC_ALL=C` for any sort; MUST byte-preserve the source body. **Implements**: FR-006, NFR-003.
- [X] **T011** `[impl-governance]` Update `plugin-kiln/skills/kiln-roadmap/SKILL.md` with a new Step N "Promote source" branch that activates on `--promote <arg>`. Resolve `<arg>` to a path (GitHub issue-number form per contract). Drive the coached interview with source pre-fill when body ≥ 200 chars (Clarification 5). Call `promote-source.sh`. **Implements**: FR-006.
- [X] **T012** `[impl-governance]` Make T006..T009 pass. Commit Phase 2 with message `feat(workflow-governance): /kiln:kiln-roadmap --promote path (FR-006)`.

**Checkpoint**: Promotion path is viable. Phase 3 can graft onto it.

---

## Phase 3 — Distill Gate + Grandfathering (impl-governance)

**Depends on**: Phase 2.

**Goal**: `/kiln:kiln-distill` refuses un-promoted sources and offers per-entry promotion hand-off; grandfathered PRDs continue to parse.

### Tests

- [X] **T013** `[impl-governance]` Create fixture `plugin-kiln/tests/distill-gate-refuses-un-promoted/` — 3 open issues, 0 roadmap items citing them. Run `/kiln:kiln-distill <theme>` with "skip all" responses. Assert no PRD emitted, per-entry prompt surfaced, exit 0, no side-effect writes. **Validates**: FR-004, FR-005 (Acceptance Scenario 1 and 3), SC-002.
- [X] **T014** `[P]` `[impl-governance]` Create fixture `plugin-kiln/tests/distill-gate-accepts-promoted/` — 1 promoted roadmap item + 2 un-promoted issues. Run with "accept entry 1, skip 2" responses. Assert: entry 1 promoted + bundled, entries 2 ignored, PRD emitted once promotion completes. **Validates**: FR-005 (Acceptance Scenario 2 and 4).
- [X] **T015** `[P]` `[impl-governance]` Create fixture `plugin-kiln/tests/distill-gate-grandfathered-prd/` — copy `docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md` into the fixture and run the gate's parser over it. Assert parses clean, no warning. **Validates**: FR-008, NFR-005, SC-006.
- [X] **T016** `[P]` `[impl-governance]` Create fixture `plugin-kiln/tests/distill-gate-three-group-shape/` — emit a PRD from a bundle containing only `item` group entries; assert the resulting `derived_from:` frontmatter still shows the three-group shape (feedback → item → issue) with empty groups rendering as absent sub-lists per FR-007. **Validates**: FR-007.

### Implementation

- [X] **T017** `[impl-governance]` Implement `plugin-kiln/scripts/distill/detect-un-promoted.sh` per `contracts/interfaces.md` Module 1. **Implements**: FR-004.
- [X] **T018** `[P]` `[impl-governance]` Implement `plugin-kiln/scripts/distill/invoke-promote-handoff.sh` per `contracts/interfaces.md` Module 1. **Implements**: FR-005.
- [X] **T019** `[impl-governance]` Update `plugin-kiln/skills/kiln-distill/SKILL.md` with a new Step 0.5 that runs between Step 0 (flag parsing) and Step 1 (three-stream ingestion). Step 0.5 calls `detect-un-promoted.sh` on the candidate bundle, invokes `invoke-promote-handoff.sh` on any un-promoted entries, re-reads the bundle after promotion, and refuses to emit a PRD if zero promoted entries remain. **Implements**: FR-004, FR-005.
- [X] **T020** `[P]` `[impl-governance]` Update `plugin-kiln/skills/kiln-distill/SKILL.md` Step 7 (derived_from emission) to always emit three-group shape with absent sub-lists on empty groups. **Implements**: FR-007.
- [X] **T021** `[P]` `[impl-governance]` Add grandfathering guard to the distill gate's parser — PRDs with `distilled_date:` before `2026-04-24` (the rollout date — record in a gate-local constant) bypass the new-gate assertions. **Implements**: FR-008.
- [X] **T022** `[impl-governance]` Make T013..T016 pass. Commit Phase 3 with message `feat(workflow-governance): distill gate refuses un-promoted sources (FR-004/005/007/008)`.

**Checkpoint**: Track A complete through Phase 3. Send phase-complete signal to team-lead.

---

## Phase 4 — `/kiln:kiln-pi-apply` Skill (impl-pi-apply)

**Depends on**: Nothing upstream (independent release per NFR-004).

**Goal**: New skill `/kiln:kiln-pi-apply` that fetches GitHub retrospective issues, parses PI blocks, classifies status, emits a propose-don't-apply diff report with stable dedup hashing.

### Tests

- [X] **T023** `[impl-pi-apply]` Create fixture `plugin-kiln/tests/pi-apply-report-basic/` — 3 canned retro issues (simulating #147, #149, #152) with 5 PI blocks (2 already-applied, 1 stale, 2 actionable). Mock `gh issue list` via a fixture-local stub. Run `/kiln:kiln-pi-apply`. Assert report at `.kiln/logs/pi-apply-<ts>.md` with correct section counts and all required fields per `contracts/interfaces.md` Module 3. **Validates**: FR-009, FR-010, FR-011, SC-004, SC-005.
- [X] **T024** `[P]` `[impl-pi-apply]` Create fixture `plugin-kiln/tests/pi-apply-status-classification/` — one PI per status branch (already-applied / stale / actionable). Assert correct classification and correct diff-rendering discipline (diff emitted only for `actionable`). **Validates**: FR-012.
- [X] **T025** `[P]` `[impl-pi-apply]` Create fixture `plugin-kiln/tests/pi-apply-dedup-determinism/` — run `/kiln:kiln-pi-apply` twice within the same minute against an identical retro backlog. Assert report bodies (everything after the header timestamp line) are byte-identical. **Validates**: FR-011 `pi-hash` stability, SC-004.
- [X] **T026** `[P]` `[impl-pi-apply]` Create fixture `plugin-kiln/tests/pi-apply-propose-only/` — assert no file under `plugin-kiln/skills/` or `plugin-kiln/agents/` has been modified after running `/kiln:kiln-pi-apply` on actionable PIs. **Validates**: FR-010 propose-don't-apply discipline.
- [X] **T027** `[P]` `[impl-pi-apply]` Create fixture `plugin-kiln/tests/pi-apply-malformed-block/` — one retro issue with a PI block missing the "Why" field. Assert the block is listed under `Parse Errors` with line range and issue URL; other blocks continue to parse. **Validates**: Edge case from spec.
- [X] **T028** `[P]` `[impl-pi-apply]` Create fixture `plugin-kiln/tests/pi-apply-empty-backlog/` — zero open retro issues. Assert report reads "No open retro issues found" and exit 0. **Validates**: Edge case from spec.

### Implementation

- [X] **T029** `[impl-pi-apply]` Implement `plugin-kiln/scripts/pi-apply/fetch-retro-issues.sh` per `contracts/interfaces.md` Module 3. **Implements**: FR-009.
- [X] **T030** `[P]` `[impl-pi-apply]` Implement `plugin-kiln/scripts/pi-apply/parse-pi-blocks.sh` per contract. **Implements**: FR-009.
- [X] **T031** `[P]` `[impl-pi-apply]` Implement `plugin-kiln/scripts/pi-apply/compute-pi-hash.sh` per contract (Clarification 7). MUST handle macOS `shasum` fallback. **Implements**: FR-011.
- [X] **T032** `[P]` `[impl-pi-apply]` Implement `plugin-kiln/scripts/pi-apply/classify-pi-status.sh` per contract. **Implements**: FR-012.
- [X] **T033** `[P]` `[impl-pi-apply]` Implement `plugin-kiln/scripts/pi-apply/render-pi-diff.sh` per contract. **Implements**: FR-011.
- [X] **T034** `[impl-pi-apply]` Implement `plugin-kiln/scripts/pi-apply/emit-report.sh` per contract — strict section order, deterministic sort under `LC_ALL=C`, always emits all four sections (including empty ones). **Implements**: FR-010, SC-004 determinism.
- [X] **T035** `[impl-pi-apply]` Author `plugin-kiln/skills/kiln-pi-apply/SKILL.md` — frontmatter `name: kiln-pi-apply` + `description`; Step 0 (argv — none in V1); Step 1 (fetch); Step 2 (parse per-issue); Step 3 (classify); Step 4 (render for actionable, compute pi-hash); Step 5 (emit report); Step 6 (user-visible summary). **Implements**: FR-009, FR-010, FR-011, FR-012.
- [X] **T036** `[impl-pi-apply]` Add `plugin-kiln/.claude-plugin/plugin.json` registration if needed (confirmed — current plugin.json auto-discovers skills from `plugin-kiln/skills/*`; no-op). **Implements**: FR-009.
- [X] **T037** `[impl-pi-apply]` Update `plugin-kiln/skills/kiln-next/SKILL.md` — add a thin discovery section that counts open retro issues via `gh` and, when count ≥ 3 per Clarification 8, surfaces `/kiln:kiln-pi-apply` as a queued maintenance recommendation. **Implements**: FR-013.
- [X] **T038** `[impl-pi-apply]` Make T023..T028 pass. Commit Phase 4 with message `feat(workflow-governance): /kiln:kiln-pi-apply skill + helpers (FR-009..FR-013)`.

**Checkpoint**: Track B complete. Send phase-complete signal to team-lead.

---

## Phase 5 — Integration + CLAUDE.md Polish (impl-governance coordinates)

**Depends on**: Phases 1–4.

**Goal**: Land Recent Changes entry, command list updates, and verify cross-skill coupling (e.g., `/kiln:kiln-next` surfaces `/kiln:kiln-pi-apply` as expected in a manual smoke test).

- [X] **T039** `[impl-governance]` Update `CLAUDE.md` "Available Commands" section — add `/kiln:kiln-roadmap --promote <source>` to the roadmap entry's flag list; add a new `/kiln:kiln-pi-apply` entry modeled on `/kiln:kiln-claude-audit`. **Implements**: documentation completeness.
- [X] **T040** `[impl-governance]` Update `CLAUDE.md` "Recent Changes" top entry to describe `build/workflow-governance-20260424` — list the three sub-initiatives and FR coverage. Trim older entry per the 5-entry cap.
- [X] **T041** `[impl-governance]` Update `CLAUDE.md` "Active Technologies" with `Bash 5.x + gh CLI + sha256sum/shasum (pi-apply), jq (retro JSON parse)` (build/workflow-governance-20260424) — per the 5-entry cap.
- [ ] **T042** `[impl-governance]` Manual smoke test — run `/kiln:kiln-next` in a temp repo seeded with 3 open retro issues and assert the output surfaces `/kiln:kiln-pi-apply` as a queued maintenance task. (This is the human-observable FR-013 check.) **Validates**: FR-013.
- [X] **T043** `[impl-governance]` Mark all tasks `[X]` in `specs/workflow-governance/tasks.md`. Commit Phase 5 with message `docs(workflow-governance): CLAUDE.md recent changes + command list`.

---

## Success Criteria Validation (final gate before /audit)

Map each SC to the fixture(s) and manual steps that validate it:

- **SC-001** (no hook blocks during build-prd) — validated by running this very pipeline; absence of `require-feature-branch` entries in `.kiln/logs/` after completion is the check.
- **SC-002** (distill refuses un-promoted) — T013.
- **SC-003** (promote creates valid item + back-ref) — T006 + T007.
- **SC-004** (pi-apply determinism) — T025.
- **SC-005** (PI-1 R-1 surfaced) — T023 (the fixture seeds PI-1 targeting `plugin-kiln/agents/prd-auditor.md`).
- **SC-006** (grandfathered PRD parses) — T015.

---

## Parallelization Summary

```text
Time ─────────────────────────────────────────────────────>

Track A (impl-governance):
  Phase 1 (T001..T005) ──┐
                         └─ Phase 2 (T006..T012) ──┐
                                                   └─ Phase 3 (T013..T022) ──┐
                                                                              └─ Phase 5 (T039..T043)
Track B (impl-pi-apply):
  Phase 4 (T023..T038) ────────────────────────────────────────────────────────┘
```

Within each phase, tasks marked `[P]` are safe to parallelize (disjoint files). Non-`[P]` tasks within a phase are sequential.

---

## Total

- **Phase 1**: 5 tasks
- **Phase 2**: 7 tasks
- **Phase 3**: 10 tasks
- **Phase 4**: 16 tasks
- **Phase 5**: 5 tasks

**Grand total**: 43 tasks across two implementer tracks.
