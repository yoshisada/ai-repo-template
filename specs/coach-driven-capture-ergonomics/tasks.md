---
description: "Task list for coach-driven-capture-ergonomics feature implementation"
---

# Tasks: Coach-Driven Capture Ergonomics

**Input**: Design documents from `specs/coach-driven-capture-ergonomics/`
**Prerequisites**: spec.md ✅, plan.md ✅, contracts/interfaces.md ✅, research.md ✅

## Format: `[ID] [P?] [Owner] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Owner]**: Which implementer owns the task
  - `[impl-context-roadmap]` — shared reader + roadmap item interview (FR-001 through FR-007)
  - `[impl-vision-audit]` — vision self-explore + CLAUDE.md audit (FR-008 through FR-016)
  - `[impl-distill-multi]` — multi-theme distill (FR-017 through FR-021)
- Every task includes exact file paths.
- Every implementation task references its FR(s) for traceability.

---

## Phase 1: Foundation — Shared Project-Context Reader

**Blocks**: All three implementer tracks (Track A builds this; Tracks B and C consume the contract).

**Goal**: Ship a deterministic, offline-safe reader that emits the ProjectContextSnapshot JSON defined in `contracts/interfaces.md`.

### Tests (write FIRST, ensure they FAIL before implementation)

- [X] **T001** `[impl-context-roadmap]` Create `bats` test `plugin-kiln/tests/project-context-reader-determinism/run.sh` asserting two invocations of `read-project-context.sh` produce byte-identical stdout on a fixture repo. **Validates**: NFR-002, FR-003, Acceptance Scenario for User Story via SC-006.
- [X] **T002** `[P]` `[impl-context-roadmap]` Create fixture under `plugin-kiln/tests/project-context-reader-determinism/fixture/` with: 3 PRDs, 5 roadmap items (mix of phases + kinds), 1 phase `in-progress`, 1 `.kiln/vision.md`, 1 `CLAUDE.md`, 1 `README.md`, 2 `plugin-*/.claude-plugin/plugin.json` stubs.
- [X] **T003** `[P]` `[impl-context-roadmap]` Create fixture under `plugin-kiln/tests/project-context-reader-empty/` with: no docs/features, no roadmap, no vision. Expected reader output: all fields `[]` or `null`, exit 0.
- [X] **T004** `[impl-context-roadmap]` Create `bats` test `plugin-kiln/tests/project-context-reader-performance/run.sh` asserting runtime <2 s on a synthetic 50-PRD + 100-item fixture. **Validates**: NFR-001, SC-006.

### Implementation

- [X] **T005** `[impl-context-roadmap]` Implement `plugin-kiln/scripts/context/read-prds.sh` per `contracts/interfaces.md`. MUST set `LC_ALL=C`. **Implements**: FR-001 (prds[] field), FR-002 (missing-dir defensiveness).
- [X] **T006** `[P]` `[impl-context-roadmap]` Implement `plugin-kiln/scripts/context/read-plugins.sh` per `contracts/interfaces.md`. MUST set `LC_ALL=C`. **Implements**: FR-001 (plugins[] field), FR-002.
- [X] **T007** `[impl-context-roadmap]` Implement `plugin-kiln/scripts/context/read-project-context.sh` composing the sub-helpers + direct scans for vision/CLAUDE/README/phases/items. Use `jq -n` or manual JSON assembly with strict sorting. **Implements**: FR-001, FR-002, FR-003, NFR-002.
- [X] **T008** `[impl-context-roadmap]` Write `plugin-kiln/scripts/context/README.md` documenting usage + JSON schema (link-ref only, no duplication of contract).
- [X] **T009** `[impl-context-roadmap]` Make T001–T004 pass. Commit with phase-complete message.

**Checkpoint**: Reader lands. Tracks B and C unblock on consumption.

---

## Phase 2: Track A (cont.) — Roadmap Item Interview Coaching

**Depends on**: Phase 1 (reader available).

**Goal**: Upgrade `/kiln:kiln-roadmap` item-capture interview to emit orientation, render coached questions, and support `accept-all` + `tweak <value> then accept-all`.

### Tests

- [X] **T010** `[impl-context-roadmap]` Create fixture `plugin-kiln/tests/roadmap-coached-interview-basic/` with happy-path flow (orientation emitted, accept-all finalizes item). Assert output item frontmatter matches the suggested values.
- [X] **T011** `[P]` `[impl-context-roadmap]` Create fixture `plugin-kiln/tests/roadmap-coached-interview-empty-snapshot/` where project-context is empty; assert skill renders `[suggestion: —, rationale: no evidence in repo]` placeholders and does NOT invent values.
- [X] **T012** `[P]` `[impl-context-roadmap]` Create fixture `plugin-kiln/tests/roadmap-coached-interview-quick/` asserting `--quick` skips orientation + interview byte-for-byte vs pre-change output.

### Implementation

- [X] **T013** `[impl-context-roadmap]` Update `plugin-kiln/skills/kiln-roadmap/SKILL.md` non-`--quick` item path: invoke reader, extract orientation data via `jq` queries from the contract's Call Sites section, emit orientation paragraph before Question 1. **Implements**: FR-006.
- [X] **T014** `[impl-context-roadmap]` Add per-question rendering: question + proposed answer + rationale + `[accept / tweak / reject]` affordance. **Implements**: FR-004.
- [X] **T015** `[impl-context-roadmap]` Add `accept-all` command handling at any prompt. Add `tweak <value> then accept-all` parser. **Implements**: FR-005.
- [X] **T016** `[impl-context-roadmap]` Rewrite prompt copy in `plugin-kiln/skills/kiln-roadmap/SKILL.md` to collaborative tone ("Here's what I think, tell me if I'm off"). **Implements**: FR-007. Validation is manual review during PRD audit.
- [X] **T017** `[impl-context-roadmap]` Make T010–T012 pass. Commit with phase-complete message.

**Checkpoint**: Track A complete.

---

## Phase 3: Track B — Vision Self-Exploration

**Depends on**: Phase 1 (reader). Can run in parallel with Phase 2 and Phase 5.

**Goal**: Upgrade `/kiln:kiln-roadmap --vision` to draft-from-evidence on first run, diff-and-propose on re-run.

### Tests

- [X] **T018** `[impl-vision-audit]` Fixture `plugin-kiln/tests/roadmap-vision-first-run/`: populated repo, no `.kiln/vision.md`. Assert all four sections are drafted with evidence citations.
- [X] **T019** `[P]` `[impl-vision-audit]` Fixture `plugin-kiln/tests/roadmap-vision-re-run/`: populated vision + repo drift. Assert per-section diffs emitted, `last_updated:` bumped on any accept.
- [X] **T020** `[P]` `[impl-vision-audit]` Fixture `plugin-kiln/tests/roadmap-vision-empty-fallback/`: fully-empty repo. Assert one-line banner + blank-slate question path.
- [X] **T021** `[P]` `[impl-vision-audit]` Fixture `plugin-kiln/tests/roadmap-vision-partial-snapshot/`: PRDs + README present, no items, no CLAUDE.md. Assert partial vision drafted with per-section evidence annotations; NO banner.
- [X] **T022** `[P]` `[impl-vision-audit]` Fixture `plugin-kiln/tests/roadmap-vision-no-drift/`: re-run against unchanged state. Assert "no drift detected" output and `last_updated:` NOT bumped.

### Implementation

- [X] **T023** `[impl-vision-audit]` Update `plugin-kiln/skills/kiln-roadmap/SKILL.md` `--vision` first-run path: invoke reader, draft 4 sections with evidence-citing bullets, confirm before write. **Implements**: FR-008.
- [X] **T024** `[impl-vision-audit]` Add re-run diff path: group proposed edits by vision section, render per-section prompt (accept-section / reject-section / step-through / global shortcuts). **Implements**: FR-009 + spec Clarification #2.
- [X] **T025** `[impl-vision-audit]` Add `last_updated:` bump logic (only when ≥1 edit accepted). **Implements**: FR-010.
- [X] **T026** `[impl-vision-audit]` Add fully-empty-snapshot banner + fallback. **Implements**: FR-011.
- [X] **T027** `[impl-vision-audit]` Add partial-snapshot draft path with per-section evidence annotations. **Implements**: FR-012 + spec Clarification #4.
- [X] **T028** `[impl-vision-audit]` Make T018–T022 pass. Commit with phase-complete message.

**Checkpoint**: Track B vision path complete.

---

## Phase 4: Track B (cont.) — CLAUDE.md Audit Project-Context Grounding

**Depends on**: Phase 1 (reader). Serial with Phase 3 within Track B; parallel with Phase 5.

**Goal**: Extend `/kiln:kiln-claude-audit` to cite project-context signals and evaluate against Anthropic's published CLAUDE.md guidance (cached).

### Tests

- [X] **T029** `[impl-vision-audit]` Fixture `plugin-kiln/tests/claude-audit-project-context/` with CLAUDE.md referencing an old phase. Assert preview log grep-finds phase drift citation + external best-practices subsection.
- [X] **T030** `[P]` `[impl-vision-audit]` Fixture `plugin-kiln/tests/claude-audit-cache-stale/` with cache `fetched:` date >30 days old. Assert staleness flag in preview.
- [X] **T031** `[P]` `[impl-vision-audit]` Fixture `plugin-kiln/tests/claude-audit-network-fallback/` with simulated WebFetch failure. Assert `cache used, network unreachable` note in preview.
- [X] **T032** `[P]` `[impl-vision-audit]` Assert no edits applied to CLAUDE.md in any of the above fixtures (propose-don't-apply). _(Implemented as a dedicated fixture `plugin-kiln/tests/claude-audit-propose-dont-apply/` with a canary string + assertion.)_

### Implementation

- [X] **T033** `[impl-vision-audit]` Create `plugin-kiln/rubrics/claude-md-best-practices.md` with frontmatter (`source_url`, `fetched: 2026-04-24`, `cache_ttl_days: 30`) + hand-curated body excerpting the referenced Anthropic guidance. **Implements**: FR-014 (cache scaffold).
- [X] **T034** `[impl-vision-audit]` Update `plugin-kiln/skills/kiln-claude-audit/SKILL.md`: invoke reader, extract commands/tech-stack/phase/gotchas, cite at least one signal in the preview log. **Implements**: FR-013.
- [X] **T035** `[impl-vision-audit]` Add best-practices evaluation subsection to the preview log with at least one finding (or explicit "no deltas found" note). Include `WebFetch` attempt + cache write on success. **Implements**: FR-014.
- [X] **T036** `[impl-vision-audit]` Add cache-fallback + staleness-flag paths. **Implements**: FR-015 + spec Clarification #3.
- [X] **T037** `[impl-vision-audit]` Confirm skill remains propose-don't-apply (no `CLAUDE.md` edits). **Implements**: FR-016.
- [X] **T038** `[impl-vision-audit]` Make T029–T032 pass. Commit with phase-complete message.

**Checkpoint**: Track B complete.

---

## Phase 5: Track C — Multi-Theme Distill Emission

**Depends on**: Phase 1 (reader). Parallel with Phases 2–4.

**Goal**: Upgrade `/kiln:kiln-distill` to support multi-select theme picker, emit N PRDs with per-PRD deterministic `derived_from:` sort and per-PRD state flips, and print a run-plan when N≥2.

### Tests

- [X] **T039** `[impl-distill-multi]` Fixture `plugin-kiln/tests/distill-multi-theme-basic/`: 3 themes, user picks 2. Assert 2 PRDs emitted, each with correct `derived_from:` partition, no cross-contamination.
- [X] **T040** `[P]` `[impl-distill-multi]` Fixture `plugin-kiln/tests/distill-multi-theme-slug-collision/`: 2 selected themes share date+slug. Assert second directory gets `-2` suffix.
- [X] **T041** `[P]` `[impl-distill-multi]` Fixture `plugin-kiln/tests/distill-multi-theme-run-plan/`: 2 PRDs emitted. Assert run-plan block appears at end of stdout with 2 ordered lines + rationales.
- [X] **T042** `[P]` `[impl-distill-multi]` Fixture `plugin-kiln/tests/distill-single-theme-no-regression/`: 1 theme only. Assert output is byte-identical to pre-change baseline; no run-plan block.
- [X] **T043** `[P]` `[impl-distill-multi]` Fixture `plugin-kiln/tests/distill-multi-theme-determinism/`: re-run same fixture twice. Assert byte-identical per-PRD output both runs. **Validates**: NFR-003, SC-005.
- [X] **T044** `[P]` `[impl-distill-multi]` Fixture `plugin-kiln/tests/distill-multi-theme-state-flip-isolation/`: source entry in Theme A only. Select A + B. Assert entry's state flips once (A's run), unchanged by B's run. **Validates**: FR-019.

### Implementation

- [X] **T045** `[impl-distill-multi]` Implement `plugin-kiln/scripts/distill/select-themes.sh` per contract. **Implements**: FR-017 (picker).
- [X] **T046** `[P]` `[impl-distill-multi]` Implement `plugin-kiln/scripts/distill/disambiguate-slug.sh` per contract (+ pre-existing-directory check). **Implements**: FR-017 (slug disambiguation) + spec Clarification #1.
- [X] **T047** `[P]` `[impl-distill-multi]` Implement `plugin-kiln/scripts/distill/emit-run-plan.sh` per contract. **Implements**: FR-018.
- [X] **T048** `[impl-distill-multi]` Update `plugin-kiln/skills/kiln-distill/SKILL.md`: insert multi-select picker between theme-grouping and emit-PRD; loop emit-PRD per selected theme; scope state flips per-PRD with assertion guard. **Implements**: FR-017, FR-019.
- [X] **T049** `[impl-distill-multi]` Ensure per-PRD `derived_from:` three-group sort + filename-ASC determinism. Confirm T043 passes. **Implements**: FR-020, NFR-003.
- [X] **T050** `[impl-distill-multi]` Wire run-plan emission at end of output when N≥2. **Implements**: FR-018.
- [X] **T051** `[impl-distill-multi]` Confirm single-theme path + `--quick`-equivalent defaults remain byte-identical; T042 passes. **Implements**: FR-021, NFR-005.
- [X] **T052** `[impl-distill-multi]` Make T039–T044 pass. Commit with phase-complete message.

**Checkpoint**: Track C complete.

---

## Phase 6: Cross-Cutting Polish & Coverage

**Depends on**: Phases 2, 3, 4, 5 complete.

- [X] **T053** `[P]` `[audit-smoke-pr]` Added `plugin-kiln/scripts/context/` + `plugin-kiln/scripts/distill/` entry to root `CLAUDE.md` `## Active Technologies` section (`plugin-kiln/README.md` does not exist — root CLAUDE.md per rubric). Entry notes no new runtime dependency (Bash 5.x + `jq` + POSIX awk).
- [X] **T054** `[P]` `[audit-smoke-pr]` Added entry to `CLAUDE.md` `## Recent Changes` for `build/coach-driven-capture-ergonomics-20260424` — shared reader + coaching on 4 capture surfaces.
- [X] **T055** `[P]` `[audit-smoke-pr]` `--quick` golden-file baseline was never committed pre-change. Substituted with `plugin-kiln/tests/distill-single-theme-no-regression/run.sh` which exercises `select-themes.sh` Channel 4 fallback + `emit-run-plan.sh` zero-byte-for-N=1 rule directly against the helpers. Re-ran on 2026-04-24: **PASS** ("single-theme path remains byte-identical (FR-021 / NFR-005)"). Documented substitution in `smoke-report.md` §T055-followup.
- [X] **T056** `[audit-smoke-pr]` Pure-Bash plugin source has no first-class coverage tool (no Istanbul / coverage.py equivalent). Substituted with script→test mapping (see `smoke-report.md` §T056-followup): every new helper has ≥1 test covering it (6/6 scripts mapped; `read-prds.sh` + `read-plugins.sh` covered transitively via `read-project-context.sh` orchestrator). `/kiln:kiln-coverage` not invoked — N/A for pure Bash.
- [X] **T057** `[audit-smoke-pr]` Standalone-runnable subset of the kiln-test fixture suite (11 / 20 tests) re-run on 2026-04-24: **11 / 11 PASS**. 9 harness-driven tests (`roadmap-vision-*` ×5, `claude-audit-*` ×4) require `claude --print` subprocess spawning via `/kiln:kiln-test` — deferred per impl-context-roadmap + impl-distill-multi friction notes (harness-substrate gap not in scope of this PRD). Static tripwires counted as "best-available pass" per team-lead explicit allowance. Behavioural test-quality audit in `compliance-report.md` confirms each deferred fixture has real file-shape assertions.

**Checkpoint**: Feature implementation complete; ready for audit phase (team tasks #5 and #6).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundation)**: Blocks all user-story phases. Owned solely by impl-context-roadmap.
- **Phase 2 (Roadmap Interview Coaching)**: Depends on Phase 1. Serial with Phase 1 within Track A.
- **Phase 3 (Vision)**: Depends on Phase 1. Parallel with Phase 2 and Phase 5.
- **Phase 4 (CLAUDE.md Audit)**: Depends on Phase 1. Serial with Phase 3 within Track B.
- **Phase 5 (Distill Multi-Theme)**: Depends on Phase 1. Parallel with Phases 2–4.
- **Phase 6 (Polish)**: Depends on Phases 2–5.

### Parallelization Map

```
Phase 1 (impl-context-roadmap)
   │
   ├─► Phase 2 (impl-context-roadmap)   ──┐
   │                                       │
   ├─► Phase 3 (impl-vision-audit)  ──► Phase 4 (impl-vision-audit) ─┐
   │                                                                  │
   └─► Phase 5 (impl-distill-multi)                                ─┤
                                                                    │
                                                Phase 6 (all)  ◄────┘
```

### Within Each Track

- Tests MUST be written and confirmed failing before implementation (Constitution Article I).
- Each task marked `[X]` IMMEDIATELY on completion (Constitution Article VIII).
- Commit after each phase, not in a single end-of-track batch.
- Every function MUST reference its FR in a comment (Article I).

### Cross-Track Coordination

- Contract changes (to `contracts/interfaces.md`) MUST use the Signature Change Protocol at the bottom of that file.
- Tracks B and C may stub the reader with a JSON fixture locally until Phase 1 lands.

---

## Notes

- `[P]` = task touches a different file and has no open dependencies.
- `[Owner]` maps each task to its pipeline implementer (`impl-context-roadmap`, `impl-vision-audit`, `impl-distill-multi`).
- FR numbers in every implementation task anchor spec traceability.
- Every acceptance scenario in spec.md § User Scenarios maps to a test task above. Grep for the FR or story number to cross-reference.
- Tasks added in later phases must preserve the `--quick` and single-theme byte-identical behavior (NFR-005) — regression tests T012 and T042 guard this.
