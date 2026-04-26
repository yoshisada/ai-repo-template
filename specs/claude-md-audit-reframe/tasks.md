---
description: "Task list for CLAUDE.md Audit Reframe — content classification + plugin-guidance sync + vision sync"
---

# Tasks: CLAUDE.md Audit Reframe

**Input**: `specs/claude-md-audit-reframe/spec.md`, `specs/claude-md-audit-reframe/plan.md`, `specs/claude-md-audit-reframe/contracts/interfaces.md`
**PRD**: `docs/features/2026-04-24-claude-md-audit-reframe/PRD.md`
**Branch**: `build/claude-md-audit-reframe-20260425`

**Tests**: Yes — kiln test fixtures under `plugin-kiln/tests/claude-audit-*/`. One fixture per FR cluster + edge case + override. Tests are part of the contract for this feature, not optional.

## Format: `[ID] [P?] [Owner] [Story] Description`

- **[P]**: Can run in parallel with other [P] tasks of the same owner (different files).
- **[Owner]**: `impl-audit-logic` | `impl-plugin-guidance` | `auditor` | `retrospective`. Tasks WITHOUT an owner label belong to the specifier and are already done by this commit.
- **[Story]**: US1..US6 maps to spec.md User Stories.

## Path Conventions

- Skill body: `plugin-kiln/skills/kiln-claude-audit/SKILL.md`
- Rubric: `plugin-kiln/rubrics/claude-md-usefulness.md`
- Fixtures: `plugin-kiln/tests/claude-audit-<name>/`
- Plugin guidance files: `<plugin-dir>/.claude-plugin/claude-guidance.md` (one per first-party plugin)
- Override config: `.kiln/claude-md-audit.config` (consumer-supplied; tests use fixture-local copies)

---

## Phase 1: Setup (Specifier — DONE)

**Purpose**: spec, plan, contracts, tasks artifacts committed. No implementation.

- [X] T001 Write `specs/claude-md-audit-reframe/spec.md` (specifier — this commit)
- [X] T002 Write `specs/claude-md-audit-reframe/plan.md` (specifier — this commit)
- [X] T003 Write `specs/claude-md-audit-reframe/contracts/interfaces.md` (specifier — this commit)
- [X] T004 Write `specs/claude-md-audit-reframe/tasks.md` (specifier — this commit)
- [X] T005 Write `specs/claude-md-audit-reframe/agent-notes/specifier.md` friction note (specifier — this commit)
- [X] T006 Commit all artifacts and notify implementers via SendMessage (specifier — this commit)

**Checkpoint**: Phase 2A and Phase 2B can begin in parallel.

---

## Phase 2A: Implement audit logic (Owner: `impl-audit-logic`)

**Purpose**: Extend the skill body and rubric with all new rules, classification, sync, override grammar. Author all fixture directories. NO file under `plugin-*/.claude-plugin/claude-guidance.md` is touched here — those are owned by `impl-plugin-guidance`.

### Phase 2A.1 — Rubric extension (FR-001..FR-008, FR-019, FR-022..FR-029, FR-030, FR-031)

- [X] T010 [impl-audit-logic] Append rule entry `enumeration-bloat` to `plugin-kiln/rubrics/claude-md-usefulness.md` per contracts §1.1 (FR-002)
- [X] T011 [impl-audit-logic] Append rule entry `benefit-missing` per contracts §1.1 (FR-005)
- [X] T012 [impl-audit-logic] Append rule entry `loop-incomplete` per contracts §1.1 (FR-006)
- [X] T013 [impl-audit-logic] Append rule entry `hook-claim-mismatch` per contracts §1.1 (FR-007, FR-008)
- [X] T014 [impl-audit-logic] Append rule entry `product-undefined` with `sort_priority: top` per contracts §1.1 (FR-025)
- [X] T015 [impl-audit-logic] Append rule entry `product-slot-missing` with `target_file` + `render_section` per contracts §1.1 (FR-026)
- [X] T016 [impl-audit-logic] Append rule entry `product-section-stale` per contracts §1.1 (FR-027)
- [X] T017 [impl-audit-logic] Add `## Convention Notes` section per contracts §1.2 (FR-019)
- [X] T018 [impl-audit-logic] Add Signal Reconciliation section codifying FR-031 precedence (`enumeration-bloat` > `load-bearing-section` for `plugin-surface`) per contracts §1.4

**Checkpoint 2A.1**: Rubric parses successfully (run existing skill against any CLAUDE.md and verify it still loads). Commit.

### Phase 2A.2 — Override grammar extension (FR-017, FR-029)

- [X] T020 [impl-audit-logic] Extend Step 2 of `plugin-kiln/skills/kiln-claude-audit/SKILL.md` to parse `exclude_section_from_classification` (regex-list + `# reason:` warning) per contracts §2.1
- [X] T021 [impl-audit-logic] Extend Step 2 to parse `exclude_plugin_from_sync` per contracts §2.2
- [X] T022 [impl-audit-logic] Extend Step 2 to parse `product_sync` boolean per contracts §2.3
- [X] T023 [impl-audit-logic] Extend allowed `action` enum to include `expand-candidate | sync-candidate | correction-candidate`; ensure malformed-override fallback still triggers correctly (existing behavior preserved)
- [X] T024 [impl-audit-logic] Add Notes-section line emission for missing `# reason:` warnings per contracts §3.4

**Checkpoint 2A.2**: Override-parsing fixtures (T076, T077, T078) pass. Commit.

### Phase 2A.3 — Classification step (FR-001..FR-004)

- [X] T030 [impl-audit-logic] Add new Step 2.5 to SKILL.md "Classify CLAUDE.md sections (FR-001..FR-004)". Single LLM call per audited file; prompt enumerates section headings; response is `{ heading: classification }` JSON; failure → all sections `unclassified`
- [X] T031 [impl-audit-logic] Apply `exclude_section_from_classification` regex(es) AFTER LLM classification to override matched sections to `preference` (FR-017 + FR-003)
- [X] T032 [impl-audit-logic] Surface `unclassified` sections in Notes section per FR-004 + contracts §3.4

**Checkpoint 2A.3**: Classification fixture (T070) passes. Commit.

### Phase 2A.4 — Cheap rules (`enumeration-bloat`, `hook-claim-mismatch`, `product-undefined`, `product-section-stale`, vision-overlong sub-signal)

- [X] T040 [impl-audit-logic] [P] Implement `enumeration-bloat` in Step 3 of SKILL.md — fires on `classification == plugin-surface` not exempted (FR-002)
- [X] T041 [impl-audit-logic] [P] Implement `hook-claim-mismatch` — claim extraction + grep across `plugin-*/hooks/*.sh` (FR-007, FR-008)
- [X] T042 [impl-audit-logic] [P] Implement `product-undefined` — checks `## Product` absence AND `.kiln/vision.md` absence (FR-025)
- [X] T043 [impl-audit-logic] [P] Implement `product-section-stale` — byte-compare current `## Product` against synced composition (FR-027)
- [X] T044 [impl-audit-logic] [P] Implement vision-overlong sub-signal under `product-section-stale` per spec.md Edge Cases — fires when vision.md >40 lines and no fenced markers

**Checkpoint 2A.4**: Cheap-rule fixtures (T071, T073, T074, T079, T080) pass. Commit.

### Phase 2A.5 — Editorial rules (`benefit-missing`, `loop-incomplete`, `product-slot-missing`)

- [X] T050 [impl-audit-logic] [P] Implement `benefit-missing` (editorial) — runs only on `convention-rationale | feedback-loop` classifications (FR-005)
- [X] T051 [impl-audit-logic] [P] Implement `loop-incomplete` (editorial) — checks repo capture surfaces + CLAUDE.md mention of `/kiln:kiln-distill` (FR-006)
- [X] T052 [impl-audit-logic] [P] Implement `product-slot-missing` (editorial) — runs against `.kiln/vision.md` per slot (FR-026)
- [X] T053 [impl-audit-logic] Wire `product-slot-missing` findings to render under `### Vision.md Coverage` sub-section per contracts §3.2

**Checkpoint 2A.5**: Editorial-rule fixtures (T072, T075, T081) pass. Commit.

### Phase 2A.6 — Plugin guidance sync (FR-011..FR-016)

- [X] T060 [impl-audit-logic] Implement plugin enumeration per contracts §5 — union of `.claude/settings.json` + `~/.claude/settings.json` `enabledPlugins` keys, `LC_ALL=C sort -u`
- [X] T061 [impl-audit-logic] Implement path resolution per contracts §6 — source-repo → versioned cache → fallback cache; honor `exclude_plugin_from_sync` override (FR-012)
- [X] T062 [impl-audit-logic] Implement guidance-file read with silent skip on missing/empty/malformed (FR-013, plus spec.md Edge Cases)
- [X] T063 [impl-audit-logic] Implement `## Plugins` section composer per contracts §3.1 — alphabetical order, header demotion (`## When to use` → `#### When to use`), trailing FR-016 blockquote (FR-014)
- [X] T064 [impl-audit-logic] Implement plugin-sync diff: insert / replace / no-op / remove based on byte-compare against current `## Plugins` (FR-015, FR-016)
- [X] T065 [impl-audit-logic] Render `## Plugins Sync` output section per contracts §3.1 (always rendered when ≥1 plugin enabled)

**Checkpoint 2A.6**: Plugin-sync fixtures (T082, T083, T084, T077) pass. Commit.

### Phase 2A.7 — Vision sync (FR-022..FR-029)

- [X] T066 [impl-audit-logic] Implement vision.md region selection per contracts §3.2 + FR-023 (whole file ≤40 lines, fenced region otherwise, sub-signal when overlong without markers)
- [X] T067 [impl-audit-logic] Implement header demotion per FR-028 (`#` → `## Product`, `##` → `###`)
- [X] T068 [impl-audit-logic] Implement `## Product` section composer + diff (insert/replace/no-op) per FR-027 + contracts §3.2
- [X] T069 [impl-audit-logic] Honor `product_sync = false` override — suppress all `product-*` rules and skip `## Vision Sync` rendering (FR-029)
- [X] T069a [impl-audit-logic] Render `## Vision Sync` output section per contracts §3.2

**Checkpoint 2A.7**: Vision-sync fixtures (T085, T086, T087, T088, T079) pass. Commit.

### Phase 2A.8 — Output rendering + idempotence + Notes

- [X] T069b [impl-audit-logic] Wire `sort_priority: top` in Signal Summary sort (only `product-undefined` triggers it currently) per contracts §3.3
- [X] T069c [impl-audit-logic] Add Notes-section emissions per contracts §3.4 — Anthropic URL line (always), FR-016 reminder (when sync proposes a change), missing-reason warnings (per override), `unclassified` defaults (per LLM-failed section)
- [X] T069d [impl-audit-logic] Verify NFR-002 idempotence — two runs on unchanged inputs produce byte-identical Signal Summary + Proposed Diff + `## Plugins Sync` + `## Vision Sync` per contracts §7. Manually run twice on a frozen fixture and `diff -u` the outputs (timestamp line excepted). (Verified by SKILL.md §Idempotence sort spec — fixture-level smoke test deferred to auditor's T203.)

**Checkpoint 2A.8**: Skill body extension complete. Commit.

### Phase 2A.9 — Fixtures (one per FR cluster — kiln-test format)

Each fixture directory under `plugin-kiln/tests/` follows the existing `claude-audit-*/` convention: `run.sh` runs the skill against fixture inputs, asserts on the produced log file. See existing `claude-audit-cache-stale/` and `claude-audit-network-fallback/` for shape.

- [X] T070 [impl-audit-logic] [P] [US3] `claude-audit-classification/` — verify FR-001..FR-004 (classification produces all 6 enum values; `unclassified` defaults to keep)
- [X] T071 [impl-audit-logic] [P] [US3] `claude-audit-enumeration-bloat/` — verify FR-002 (plugin-surface section flagged removal-candidate; rationale text matches)
- [X] T072 [impl-audit-logic] [P] [US3] `claude-audit-benefit-missing/` — verify FR-005 (rationale-bearing section unflagged; rationale-missing section flagged expand-candidate with `Why:` placeholder)
- [X] T073 [impl-audit-logic] [P] [US5] `claude-audit-loop-incomplete/` — verify FR-006 (capture-surface populated + no `/kiln:kiln-distill` mention → fires; both present → unfires)
- [X] T074 [impl-audit-logic] [P] [US4] `claude-audit-hook-claim-mismatch/` — verify FR-007 (claim with hook-grep hit → unfires; orphan claim → fires)
- [X] T075 [impl-audit-logic] [P] `claude-audit-existing-rules-regression/` — verify SC-010 (re-run of pre-existing rule fixtures continues to fire correctly)
- [X] T076 [impl-audit-logic] [P] [US3] `claude-audit-override-section/` — verify FR-017 `exclude_section_from_classification` (matched section classified as preference; `enumeration-bloat` does not fire)
- [X] T077 [impl-audit-logic] [P] [US1] `claude-audit-override-plugin/` — verify FR-017 `exclude_plugin_from_sync` (listed plugin skipped during sync)
- [X] T078 [impl-audit-logic] [P] [US2] `claude-audit-override-product-sync/` — verify FR-029 `product_sync = false` (all `product-*` rules suppressed)
- [X] T079 [impl-audit-logic] [P] [US2] `claude-audit-product-undefined/` — verify FR-025 (rule fires AND signal appears at row 1 of Signal Summary table per SC-007)
- [X] T080 [impl-audit-logic] [P] [US2] `claude-audit-product-stale/` — verify FR-027 (current `## Product` differs from synced composition → sync-candidate)
- [X] T081 [impl-audit-logic] [P] [US2] `claude-audit-product-slot-missing/` — verify FR-026 (empty/placeholder slot fires; output rendered under `### Vision.md Coverage`)
- [X] T082 [impl-audit-logic] [P] [US1] `claude-audit-plugins-sync/` — verify FR-014, FR-015 (US1 AC#1 — section absent → insert; US1 AC#3 — section matches → no diff). Depends on `impl-plugin-guidance` having shipped at least 2 reference guidance files (kiln + shelf)
- [X] T083 [impl-audit-logic] [P] [US1] `claude-audit-plugins-sync-disabled/` — verify FR-015 (US1 AC#2 — disabled plugin's subsection removed only)
- [X] T084 [impl-audit-logic] [P] [US1] `claude-audit-plugins-sync-missing/` — verify FR-013 (plugin without guidance file silently skipped — no signal, no warning)
- [X] T085 [impl-audit-logic] [P] [US2] `claude-audit-product-sync/` — verify FR-022, FR-023 whole-file mode, FR-028 header demotion (US2 AC#1)
- [X] T086 [impl-audit-logic] [P] [US2] `claude-audit-vision-fenced/` — verify FR-023 fenced region (US2 AC#2)
- [X] T087 [impl-audit-logic] [P] [US2] `claude-audit-vision-overlong/` — verify spec.md Edge Cases (vision.md >40 lines without markers → sub-signal under `product-section-stale`)
- [X] T088 [impl-audit-logic] [P] [US6] `claude-audit-plugin-author-update/` — verify US6 AC#1 (updated guidance file → diff swaps only that subsection). Depends on `impl-plugin-guidance` having shipped kiln's guidance file

**Checkpoint 2A.9**: All fixtures pass via `/kiln:kiln-test plugin-kiln`. Write `specs/claude-md-audit-reframe/agent-notes/impl-audit-logic.md` friction note. Commit.

---

## Phase 2B: Implement plugin guidance reference files (Owner: `impl-plugin-guidance`)

**Purpose**: Author the five first-party `.claude-plugin/claude-guidance.md` files per contracts §4. Pure content; touches NO skill / rubric / hook code. All five files can be authored in parallel.

### Phase 2B.1 — Author guidance files

- [X] T100 [impl-plugin-guidance] [P] Author `plugin-kiln/.claude-plugin/claude-guidance.md` per contracts §4 — `## When to use` (required) describes the spec-first / 4-gate / capture-loop philosophy; `## Key feedback loop` (recommended) cites `/kiln:kiln-report-issue` → `/kiln:kiln-distill` → PRD chain; `## Non-obvious behavior` (recommended) covers the 4-gate hooks
- [X] T101 [impl-plugin-guidance] [P] Author `plugin-shelf/.claude-plugin/claude-guidance.md` — `## When to use` describes Obsidian mirror / project-context bridge; `## Key feedback loop` cites the `@inbox/open/` proposal flow; `## Non-obvious behavior` covers `.shelf-config` and the `shelf_full_sync_threshold` counter
- [X] T102 [impl-plugin-guidance] [P] Author `plugin-wheel/.claude-plugin/claude-guidance.md` — `## When to use` describes wheel as plugin-agnostic dispatch infrastructure (per `.kiln/vision.md` constraint); `## Non-obvious behavior` covers `WORKFLOW_PLUGIN_DIR` and the agent resolver primitive
- [X] T103 [impl-plugin-guidance] [P] Author `plugin-clay/.claude-plugin/claude-guidance.md` — `## When to use` describes idea → repo scaffolding pipeline; `## Key feedback loop` cites the `/clay:clay-idea` → `/clay:clay-create-repo` chain
- [X] T104 [impl-plugin-guidance] [P] Author `plugin-trim/.claude-plugin/claude-guidance.md` — `## When to use` describes Penpot ↔ code design sync; `## Key feedback loop` cites `trim-pull` / `trim-push` mirror behavior

### Phase 2B.2 — Self-verify against §4.4 checklist

- [X] T110 [impl-plugin-guidance] Run the §4.4 manual checklist against each authored file (path correct, `## When to use` first + 1–3 sentences, no enumerations / commands / agents / hooks / workflow paths, 10–30 lines, single trailing newline). Document deviations in friction note.
- [X] T111 [impl-plugin-guidance] Write `specs/claude-md-audit-reframe/agent-notes/impl-plugin-guidance.md` friction note. Commit all five files + the note in one commit.

**Checkpoint 2B**: Five guidance files committed. Notify `impl-audit-logic` so they can run T082/T088 (which depend on these files existing). Notify `auditor` once self-verification is complete.

---

## Phase 3: Audit + smoke test + create PR (Owner: `auditor`)

- [X] T200 [auditor] Run `/kiln:audit` against the merged tree of Phase 2A + Phase 2B work. Verify every PRD FR has spec coverage, code (skill/rubric body or guidance file), and ≥1 fixture. Document any gaps in `specs/claude-md-audit-reframe/blockers.md`
- [X] T201 [auditor] Run `/kiln:kiln-test plugin-kiln` end-to-end. Verify all 19 new fixtures pass + 0 regressions in pre-existing fixtures (SC-010)
- [X] T202 [auditor] Run `/kiln:kiln-claude-audit` against the source kiln repo's actual CLAUDE.md and review the produced log under `.kiln/logs/`. Sanity-check: ≥3 plugins now ship guidance (SC-004); the proposed `## Plugins` section is non-empty and alphabetical; no signals fire on a section the auditor judges to be valid product/feedback-loop content
- [X] T203 [auditor] Smoke-test idempotence — run the audit twice on the source kiln repo and `diff -u` the two log files (header timestamp excepted). Verify byte-identical bodies (SC-006)
- [X] T204 [auditor] Create PR via `gh pr create` with title `CLAUDE.md audit reframe — content classification + plugin-guidance sync + vision sync`, body cites this PRD + spec, label `build-prd`. Notify `retrospective` once PR is open

**Checkpoint 3**: PR open and ready for human review. Auditor signs off.

---

## Phase 4: Retrospective (Owner: `retrospective`)

- [ ] T300 [retrospective] Analyze prompt + communication effectiveness across the pipeline. Review all `agent-notes/*.md` friction notes. File any retro-driven manifest improvements via `/kiln:kiln-pi-apply` workflow (out-of-scope here; just file the GitHub issue with `label:retrospective`)

**Checkpoint 4**: Retrospective issue filed. Pipeline complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (specifier)**: No dependencies — DONE in this commit.
- **Phase 2A (`impl-audit-logic`)**: Starts after Phase 1. Internal phases 2A.1 → 2A.9 are sequential within the implementer (later phases depend on earlier). All [P]-marked tasks within a phase can run in parallel.
- **Phase 2B (`impl-plugin-guidance`)**: Starts after Phase 1, in parallel with Phase 2A.
- **Phase 2A ↔ Phase 2B coupling**: T082 and T088 in Phase 2A.9 depend on Phase 2B.1 having shipped at least the kiln + shelf guidance files (the fixtures need real guidance content to assert against). All other Phase 2A tasks have no Phase 2B dependency.
- **Phase 3 (`auditor`)**: Starts after BOTH Phase 2A and Phase 2B complete.
- **Phase 4 (`retrospective`)**: Starts after Phase 3 PR is open.

### Cross-implementer file ownership (NON-NEGOTIABLE)

Per `plan.md` Implementer File Ownership:

- `impl-audit-logic` owns: `plugin-kiln/skills/kiln-claude-audit/SKILL.md`, `plugin-kiln/rubrics/claude-md-usefulness.md`, all `plugin-kiln/tests/claude-audit-*/` directories created in this PR.
- `impl-plugin-guidance` owns: all five `plugin-*/.claude-plugin/claude-guidance.md` files.
- **Disjoint sets**: neither implementer edits files owned by the other. If `impl-plugin-guidance` discovers the audit logic needs a tweak to read their files correctly, file an issue or send a SendMessage — do NOT cross the line.

### Parallel Opportunities

- All [P]-marked tasks within Phase 2A.4 (T040..T044): parallel.
- All [P]-marked tasks within Phase 2A.5 (T050..T052): parallel.
- All [P]-marked tasks within Phase 2A.9 (T070..T088): parallel — different fixture directories, no shared files.
- All Phase 2B.1 tasks (T100..T104): parallel — five different files, single owner.
- Phase 2A and Phase 2B run end-to-end in parallel (modulo the T082/T088 → Phase 2B.1 dependency).

### Within Each Phase

- Tests (fixture directories) MUST be authored alongside the rule that drives them. Author the rule + the fixture in the same commit if practical.
- Rubric entry before skill-body wiring before fixture for any single rule.
- Override-grammar parsing before override-using fixtures.
- Plugin enumeration + path resolution before plugin-sync rendering.

---

## Implementation Strategy

### MVP First (US1 — Plugin guidance auto-syncs)

1. Specifier completes Phase 1 (this commit).
2. `impl-audit-logic` completes Phase 2A.1 → 2A.2 → 2A.3 → 2A.6 (skipping 2A.4/2A.5/2A.7 for the MVP cut).
3. `impl-plugin-guidance` completes Phase 2B in parallel.
4. Run T077, T082, T083, T084 — verify US1 acceptance scenarios pass.
5. MVP demoable: a consumer with kiln + shelf + wheel sees a deterministic `## Plugins` diff.

### Incremental Delivery

1. After MVP (US1): add US3 (enumeration-bloat / classification core) by completing Phase 2A.4 + the relevant Phase 2A.9 fixtures (T070, T071, T076).
2. Add US2 (vision sync): Phase 2A.7 + T079, T080, T081, T085, T086, T087, T078.
3. Add US4 + US5 (hook-claim, loop-incomplete): Phase 2A.4 (T041) + Phase 2A.5 (T051) + T073, T074.
4. Add US6 (plugin author update): T088 — small, layered on top of US1 mechanic.
5. Each story can ship and be reviewed independently if Phase 2A is split across multiple PRs (preferred but not required for this build pipeline).

### Parallel Team Strategy

The intended dispatch is one PR for the whole feature with the two implementers running concurrently. The team-lead's pipeline routes:

- `impl-audit-logic` → Phase 2A (all of it).
- `impl-plugin-guidance` → Phase 2B (parallel).
- `auditor` → Phase 3 (after both).
- `retrospective` → Phase 4 (after PR opens).

---

## Notes

- `[Story]` labels on fixture tasks map fixtures to user stories so the auditor can verify each US is end-to-end testable.
- All fixtures follow the existing `plugin-kiln/tests/claude-audit-*/` convention (`run.sh` + fixture inputs + assertions on `.kiln/logs/` output).
- Idempotence (NFR-002 carried forward, contracts §7) is verified manually by `auditor` (T203) — no separate fixture, but a `diff -u` smoke test at audit time.
- The propose-diff-only contract is preserved automatically because no new code path calls `Edit` / `Write` / `git apply` against CLAUDE.md. The auditor double-checks this in T200.
- Anthropic URL is cited in the rubric Convention Notes (FR-019) AND in audit Notes (FR-018, SC-009). Two distinct surfaces; both required.
- `sort_priority: top` field is new in the rubric schema — only `product-undefined` uses it currently. Future rules adding it must motivate why they need to outrank everything else.
- Commit per phase per Article VIII (Incremental Task Completion). Each `[X]` mark goes in immediately on task completion, not in a batch at the end.
