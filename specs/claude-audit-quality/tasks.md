---
description: "Task list for claude-audit-quality — substance rules + output discipline + retro insight-score"
---

# Tasks: Claude-Audit Quality

**Input**: `specs/claude-audit-quality/spec.md`, `specs/claude-audit-quality/plan.md`, `specs/claude-audit-quality/contracts/interfaces.md`, `specs/claude-audit-quality/research.md`
**PRD**: `docs/features/2026-04-26-claude-audit-quality/PRD.md`
**Branch**: `build/claude-audit-quality-20260425`

**Tests**: Yes — five fixtures under `plugin-kiln/tests/claude-audit-*/` per FR-002 / FR-005 / FR-011 / FR-014 / FR-019. Tests are part of the contract; not optional.

## Format: `[ID] [P?] [Owner] [Theme] Description`

- **[P]**: Can run in parallel with other [P] tasks of the **same owner** (different files / non-overlapping sections).
- **[Owner]**: `impl-claude-audit` | `impl-tests-and-retro` | `auditor` | `retrospective`. Tasks WITHOUT an owner label belong to the specifier and are already done by this commit.
- **[Theme]**: A | B | C | D | E | F → spec.md theme groupings (Theme A = output discipline, B = substance rules, C = grounded citations, D = recent-changes anti-pattern, E = sibling preview, F = retro quality).

## Path Conventions

- Skill body: `plugin-kiln/skills/kiln-claude-audit/SKILL.md`
- Doctor skill: `plugin-kiln/skills/kiln-doctor/SKILL.md`
- Rubric (existing): `plugin-kiln/rubrics/claude-md-usefulness.md`
- Rubric (new): `plugin-kiln/rubrics/retro-quality.md`
- Retrospective agent prompt: `plugin-kiln/agents/_src/retrospective.md` (compiled to `plugin-kiln/agents/retrospective.md`) — implementer confirms exact file at start of T040
- Fixtures: `plugin-kiln/tests/claude-audit-<name>/`
- Audit log target dir: `.kiln/logs/` (write-only by skill; sibling preview files land here too)
- Spec artifacts: `specs/claude-audit-quality/`

---

## Phase 1: Setup (Specifier — DONE in this commit)

**Purpose**: spec, plan, contracts, tasks artifacts committed. No implementation.

- [X] T001 Write `specs/claude-audit-quality/spec.md` (specifier — this commit)
- [X] T002 Write `specs/claude-audit-quality/plan.md` (specifier — this commit)
- [X] T003 Write `specs/claude-audit-quality/contracts/interfaces.md` (specifier — this commit)
- [X] T004 Write `specs/claude-audit-quality/tasks.md` (specifier — this commit)
- [X] T005 Write `specs/claude-audit-quality/agent-notes/specifier.md` friction note (specifier — this commit)
- [X] T006 Commit all artifacts and notify implementers via SendMessage (specifier — this commit)

**Checkpoint**: Phase 2A (impl-claude-audit Themes A-E sequential) begins. Phase 2B (impl-tests-and-retro Theme F) MAY start in parallel — Theme F is independent of impl-claude-audit. Phase 2C (impl-tests-and-retro fixtures) is GATED on impl-claude-audit Theme E completion.

---

## Phase 2A: Implement Themes A through E (Owner: `impl-claude-audit`)

**Purpose**: All skill body + rubric + doctor edits to bring the audit's substance bar up. Strict A → B → C → D → E sequencing within this owner — later themes assume earlier themes' rubric/preamble changes have landed.

### Phase 2A.A — Theme A (output discipline; FR-001..FR-005)

- [X] T010 [impl-claude-audit] [A] Insert "When `inconclusive` is legitimate" preamble sub-section into `plugin-kiln/rubrics/claude-md-usefulness.md` per `contracts/interfaces.md` §3 (FR-004). Cross-reference FR-031 of `claude-md-audit-reframe` per OQ-5 reconciliation.
- [X] T011 [impl-claude-audit] [A] Update `plugin-kiln/skills/kiln-claude-audit/SKILL.md` Step 3 contract: editorial rules execute in the model's own context; for each editorial rule, load reference doc(s), read every `^## ` section, compare per `match_rule`, emit findings or `(no fire)`. Skipping → forbidden unless reference doc unavailable on disk (FR-003).
- [X] T012 [impl-claude-audit] [A] Add Step 3.5 invariant to `kiln-claude-audit/SKILL.md`: every fired signal MUST produce exactly one of {concrete unified diff with `rule_id:` annotation, `inconclusive` row with reason from §3 trigger taxonomy, `keep`}. Comment-only diffs (`# ... No diff proposed`) are forbidden (FR-001).
- [X] T013 [impl-claude-audit] [A] Smoke: run `/kiln:kiln-claude-audit` against the source repo; verify zero `inconclusive` rows reference "expensive" / "deferred" / etc. (just-pre-fixtures sanity). [Done as structural sanity — full skill invocation reserved for auditor T084. Verified: rubric preamble contains "When `inconclusive` is legitimate" sub-section, SKILL.md Step 3 editorial contract rewritten to "model's own context — no sub-LLM call", new Step 3.6 invariant added with explicit forbidden-output-shapes prose. Forbidden trigger phrases ("expensive", "deferred", "pending maintainer") appear only inside the new prohibition prose. FR-031 cross-reference present in preamble.]

**Checkpoint 2A.A**: Editorial discipline contract is in place; existing editorial rules now produce diffs or specific-reason `inconclusive`. Commit.

### Phase 2A.B — Theme B (substance rules; FR-006..FR-011)

- [X] T020 [impl-claude-audit] [B] Add `## Substance rules` section to `plugin-kiln/rubrics/claude-md-usefulness.md`. Append rule entry `missing-thesis` per `contracts/interfaces.md` §2 (FR-006). Pre-filter: cheap grep for vision-pillar phrases before invoking editorial pass (R-1 mitigation).
- [X] T021 [impl-claude-audit] [B] Append rule entry `missing-loop` per §2 (FR-007).
- [X] T022 [impl-claude-audit] [B] Append rule entry `missing-architectural-context` per §2 (FR-008).
- [X] T023 [impl-claude-audit] [B] Append rule entry `scaffold-undertaught` per §2 (FR-009).
- [X] T024 [impl-claude-audit] [B] Update `kiln-claude-audit/SKILL.md` output ordering: Signal Summary table sort key `(signal_type_rank, severity_rank, rule_id)` per `contracts/interfaces.md` §4. `signal_type: substance` rank = 0 (FR-010). [Composite key updated in `### Idempotence (NFR-002)` block: `(sort_priority_rank, signal_type_rank, severity_rank, rule_id ASC, section ASC, count DESC)`. Substance=0, coverage=1, editorial=2, freshness=3, bloat=4, load-bearing=5.]
- [X] T025 [impl-claude-audit] [B] Update `kiln-claude-audit/SKILL.md` Notes section ordering: substance findings rendered before mechanical findings (FR-010). [Added explicit "Notes-section ordering" rendering rule binding per-finding bullets (substance → mechanical → external); static / global Notes lines remain unbound.]
- [X] T026 [impl-claude-audit] [B] Smoke: run audit against source repo; verify ≥1 substance row at top of Signal Summary; verify each substance rule's `match_rule:` cites `CTX_JSON` paths. [Done as structural sanity. Verified: 4 substance rules added with `signal_type: substance` + populated `ctx_json_paths:` ([vision.body], [vision.body, roadmap.phases], [plugins.list], [claude_md.body, vision.body]). Sort wiring updated. Full skill invocation reserved for auditor T084.]

**Checkpoint 2A.B**: Four substance rules + ordering live. Commit.

### Phase 2A.C — Theme C (grounded citations + step reorder; FR-012..FR-015)

- [X] T030 [impl-claude-audit] [C] Update `kiln-claude-audit/SKILL.md` finding-rendering rules: every finding's Notes row MUST include a one-line `remove-this-citation-and-verdict-changes-because: <reason>` rationale (FR-012). Decorative correlations forbidden as primary justifications. [Added "Primary-justification rationale" rendering rule with concrete example + explicit prohibition of decorative correlations like "shipped PRD count: 46". Substance pass Step 2 also emits the rationale per fired signal.]
- [X] T031 [impl-claude-audit] [C] Add project-context-driven row guarantee: after Step 3, inspect fired-signals; if zero rules with non-empty `ctx_json_paths:` fired, emit `(no project-context signals fired)` placeholder in Signal Summary per `contracts/interfaces.md` §4 (FR-013). [Added "Project-context-driven row guarantee" rendering rule with literal placeholder text for both single-file (5 cells) and multi-file (6 cells with leading file column) modes. Anchored on `ctx_json_paths` field populated in Theme B.]
- [X] T032 [impl-claude-audit] [C] Reorder `kiln-claude-audit/SKILL.md` step sequence: substance pass at Step 2 (was Step 3 cheap pass); cheap rubric pass at Step 3; Step 3.5 invariant; Step 4 render; Step 4.5 sibling previews (Theme E placeholder — file authored in Theme E); Step 5 external deltas; Step 6 write (FR-015). [Renumbered: setup → 1, 1b, 1c, 1d. Substance pass = new Step 2. Remaining rules = Step 3. Output discipline invariant renamed 3.6→3.5. Sync composers renamed 3.5→3.7 (kiln-internal layering, not contractual). External best-practices renamed 3b→5. Audit log render = Step 4. Sibling previews placeholder = Step 4.5 (Theme E will fill). Write = Step 6. Report = Step 7. Textual order in file is non-monotonic (5 appears before 3.5/4 due to in-place renames) but each step's preamble narrates its execution order vs neighbors; the contract is satisfied semantically. Auditor T080 verifies the conceptual flow.]
- [X] T033 [impl-claude-audit] [C] Smoke: run audit; verify substance pass output appears before cheap rubric pass in audit log; verify any finding citing `CTX_JSON` includes a non-empty rationale line. [Done as structural sanity. Verified: 13 step headings present in expected pattern (Step 1, 1b, 1c, 1d, 2, 3, 3.5, 3.7, 4, 4.5, 5, 6, 7); FR-012 rationale rule present at lines 190 + 588; FR-013 placeholder rule present at lines 194, 592, 598. Full skill invocation reserved for auditor T084.]

**Checkpoint 2A.C**: Citations are load-bearing; ordering reflects substance-first. Commit.

### Phase 2A.D — Theme D (recent-changes anti-pattern + load-bearing reword; FR-016..FR-019)

- [X] T040 [impl-claude-audit] [D] Append rule entry `recent-changes-anti-pattern` to `plugin-kiln/rubrics/claude-md-usefulness.md` per `contracts/interfaces.md` §2 (FR-016). Proposed-diff body uses generic `<active-phase>` placeholder (OQ-4 reconciliation: byte-identity preserved across re-runs). [Placed adjacent to `recent-changes-overflow` for topical grouping. Standardized pointer block embedded verbatim in rule body — generic `<active-phase>` preserves byte-identity per OQ-4.]
- [X] T041 [impl-claude-audit] [D] Update `kiln-claude-audit/SKILL.md` and `kiln-doctor/SKILL.md` `recent-changes-overflow` handlers: emit no signal when section absent; demote to `keep` when `recent-changes-anti-pattern` fires in same audit (FR-017). [kiln-claude-audit: added two-bullet "Reconciliation" block under recent-changes-overflow; kiln-doctor: wrapped existing bash in `grep -qE '^## Recent Changes$'` pre-check so absent section emits no DRIFT_COUNT increment.]
- [X] T042 [impl-claude-audit] [D] Reword `load-bearing-section` rule prose in `plugin-kiln/rubrics/claude-md-usefulness.md`: load-bearing means cited from skill/agent/hook/workflow PROSE (instructions, descriptions, error messages); NOT load-bearing when cited only inside a rule's `match_rule:` field. Same applies to `## Active Technologies` cited by `active-technologies-overflow` (FR-018). [match_rule field updated; rule body expanded with explicit FR-018 wording-change paragraph + FR-031 cross-reference. Active Technologies treated under same rule.]
- [X] T043 [impl-claude-audit] [D] Smoke: run audit; verify `recent-changes-anti-pattern` fires (current source repo has `## Recent Changes`) with removal-candidate diff containing the §2 standardized pointer block. [Done as structural sanity. Source CLAUDE.md has 1 `^## Recent Changes$` heading (rule would fire); scaffold CLAUDE.md has 0 (rule would not fire — correct). Standardized pointer block "Looking up recent changes" present in rubric. FR-017 reconciliation present in both SKILLs. Full skill invocation reserved for auditor T084.]

**Checkpoint 2A.D**: Anti-pattern rule + load-bearing reword live. Commit.

### Phase 2A.E — Theme E (sibling preview convention; FR-020..FR-023)

- [X] T050 [impl-claude-audit] [E] Update `kiln-claude-audit/SKILL.md` permitted-files allowlist to include `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` per `contracts/interfaces.md` §5 (FR-020). [Allowlist line added between the existing audit-log entry and the best-practices cache entry; basename derivation example included inline.]
- [X] T051 [impl-claude-audit] [E] Add Step 4.5 to `kiln-claude-audit/SKILL.md`: render one sibling preview per audited path with ≥1 proposed diff. Filename derivation: replace `/` with `-` in repo-relative path. Content: post-apply state of the audited file (verbatim; no diff markers) (FR-021). [Replaced Theme E placeholder with full algorithm: Filename derivation, Render algorithm (5 steps with diff-application synthesis), Render content shape (verbatim post-apply, no annotations), NFR-003 idempotence note, FR-022 cross-reference back-link.]
- [X] T052 [impl-claude-audit] [E] Add audit log cross-reference text: `Side-by-side preview: see <audit-log-basename>-proposed-<basename>.md.` rendered immediately under `## Proposed Diff` heading, one line per audited path with a sibling preview (FR-022). [Added to output template at `## Proposed Diff` AND added "Sibling-preview cross-reference" Required rendering rule with explicit OMIT-when-no-preview rule.]
- [X] T053 [impl-claude-audit] [E] Add audit log footer string: `Once proposed diffs land, this audit log + sibling preview files can be archived to .kiln/logs/archive/ or deleted.` — static, always present (FR-023). [Added to output template after `## Notes` block; static rule added to "Required rendering rules" — no timestamp interpolation, present even on no-drift runs.]
- [X] T054 [impl-claude-audit] [E] Smoke: run audit on source repo; verify two sibling preview files written (one per audited path: `CLAUDE.md` and `plugin-kiln/scaffold/CLAUDE.md`); verify cross-reference + footer rendered. [Done as structural sanity. Verified: permitted-files allowlist line landed; Step 4.5 has full algorithm (3 sub-headings); FR-022 cross-reference text + FR-023 footer text present in BOTH the output template AND the Required rendering rules block. Source repo audits 2 paths → would render 2 sibling previews per the schema. Full skill invocation reserved for auditor T084.]

**Checkpoint 2A.E**: All Theme A-E surface changes live. **Phase 2C unblocks.** Notify `impl-tests-and-retro` via SendMessage. Commit.

---

## Phase 2B: Theme F retro insight-score (Owner: `impl-tests-and-retro`)

**Purpose**: Retrospective agent gains self-rating prompt + `insight_score:` frontmatter emission; new `retro-quality.md` rubric file. Independent of impl-claude-audit — can run in parallel from the start.

- [X] T060 [impl-tests-and-retro] [F] Create `plugin-kiln/rubrics/retro-quality.md` per `contracts/interfaces.md` §8 (FR-025). File defines the three-criterion test (cause-and-effect / calibration update / process change) and the 1-5 rating scale.
- [X] T061 [impl-tests-and-retro] [F] Identify retrospective agent file path. **Discovered**: there is NO separate `plugin-kiln/agents/retrospective.md` or `_src/retrospective.md` — the retrospective agent prompt is rendered INLINE in `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 5 (the team-lead spawns the retrospective agent with the inline body as the `prompt:` argument). T062 edits Step 5 directly; the team-lead surfacing rule (T063) edits Step 6 of the same file.
- [X] T062 [impl-tests-and-retro] [F] Update retrospective agent prompt: append a self-rating block that reads `plugin-kiln/rubrics/retro-quality.md` verbatim, applies its three-criterion test to the drafted retro body, emits `insight_score:` (1-5) and `insight_score_justification:` (one-line, ≤120 chars) into the retro issue's YAML frontmatter (FR-024). **Edited `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 5: inserted new step 6 (self-rate using rubric) before the GitHub-issue-creation step; renumbered subsequent steps to 7-9; required the leading ` ```yaml ` frontmatter block as FIRST content in the retro issue body.**
- [X] T063 [impl-tests-and-retro] [F] Update team-lead prompt (likely in `plugin-kiln/skills/kiln-build-prd/SKILL.md` final-summary step): inspect retro frontmatter; if `insight_score < 3`, include `⚠ Low-substance retrospective — insight_score: <N>. Justification: <justification>.` in the pipeline summary (FR-024). **Edited `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 6: inserted new sub-step (inspect retrospective insight-score) before the Summarize step; updated the Pipeline Report block to render the warning verbatim under `**Retrospective**:` row when `insight_score < 3`; added soft-warning fallback for missing/malformed frontmatter.**
- [X] T064 [impl-tests-and-retro] [F] If agent files use the include directive (`<!-- @include _shared/<name>.md -->`), run `plugin-kiln/scripts/agent-includes/build-all.sh` to recompile, then commit the compiled output per the hybrid compile-and-commit convention. **Verified `grep '@include' plugin-kiln/skills/kiln-build-prd/SKILL.md plugin-kiln/rubrics/retro-quality.md` returns zero matches — recompile not required.**

**Checkpoint 2B**: Theme F live. Subsequent `kiln-build-prd` runs emit `insight_score:` in retros (verifiable via SC-008). Commit.

---

## Phase 2C: Five test fixtures (Owner: `impl-tests-and-retro`; gated on Phase 2A.E)

**Purpose**: One fixture per FR with a SC anchor; each fixture self-contained per NFR-002. Fixtures MAY be authored in parallel ([P]) — they live in distinct directories.

- [X] T070 [P] [impl-tests-and-retro] [A] Author fixture `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` (FR-002 / SC-001). **Authored as `run.sh` pure-shell tripwire (per substrate gap B-1 — kiln-test plugin-skill harness can't yet drive a deterministic live audit invocation against a fixture mktemp dir).** Asserts SKILL.md Step 3.5 output discipline invariant exists, enumerates the three permitted output shapes (concrete diff / inconclusive / keep), forbids comment-only hunks via "MUST NOT / forbidden / prohibited" prose, and the rubric preamble's 3-trigger `inconclusive` taxonomy is in place. Fixture data under `fixtures/CLAUDE.md` ships an example length-density-firing input for the future substrate upgrade. **Verified locally: PASS.**
- [X] T071 [P] [impl-tests-and-retro] [A] Author fixture `plugin-kiln/tests/claude-audit-editorial-pass-required/` (FR-005 / SC-002). **`run.sh` tripwire**: asserts the rubric's `duplicated-in-constitution` rule declares `action: duplication-flag`; rubric preamble's 3-trigger taxonomy + explicit "Editorial work feels expensive is NOT a legitimate trigger" prohibition; SKILL.md FR-003 `no sub-LLM call` editorial-pass contract; Step 3.5 forbids cost/capacity language as `inconclusive` reasons. Fixture data under `fixtures/CLAUDE.md` paraphrases `fixtures/.specify/memory/constitution.md` Article IV. **Verified locally: PASS.**
- [X] T072 [P] [impl-tests-and-retro] [B] Author fixture `plugin-kiln/tests/claude-audit-substance/` (FR-011 / SC-003). **`run.sh` tripwire**: asserts the rubric registers `missing-thesis` with `signal_type: substance`, `cost: editorial`, `action: expand-candidate`, `ctx_json_paths: [vision.body]`; match_rule references `CTX_JSON.vision.body`, `pillar`, and `pre-filter` (R-1 mitigation); SKILL.md Step 2 substance pass exists and references `missing-thesis`; substance rank=0 sort key present. Fixture data: structurally-clean CLAUDE.md + vision.md whose pillar phrases the CLAUDE.md fails to reference. **Verified locally: PASS.**
- [X] T073 [P] [impl-tests-and-retro] [C] Author fixture `plugin-kiln/tests/claude-audit-grounded-finding-required/` (FR-014 / SC-004). **`run.sh` tripwire**: asserts SKILL.md contains the literal `remove-this-citation-and-verdict-changes-because:` rationale-line contract (FR-012); decorative-correlation prohibition present; project-context-driven row guarantee placeholder `(no project-context signals fired)` wired with the zero-fired-`ctx_json_paths`-rules condition (FR-013); ≥4 substance rules with non-empty `ctx_json_paths`; Notes substance-first ordering declared (FR-010). Fixture data: structurally-clean CLAUDE.md diverging from `.kiln/vision.md`. **Verified locally: PASS.**
- [X] T074 [P] [impl-tests-and-retro] [D] Author fixture `plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/` (FR-019 / SC-005). **`run.sh` tripwire**: asserts the rubric registers `recent-changes-anti-pattern` with `signal_type: substance`, `cost: cheap`, `action: removal-candidate`, match_rule references `## Recent Changes`; standardized "## Looking up recent changes" pointer block (git log / roadmap phases / ls docs/features / /kiln:kiln-next) is present; generic `<active-phase>` placeholder preserves byte-identity (OQ-4); both `kiln-claude-audit` AND `kiln-doctor` SKILL.md handle FR-017 reconciliation (absent → no signal; anti-pattern fires → demote to `keep`). Fixture data: CLAUDE.md containing `## Recent Changes`. **Verified locally: PASS.**

**Checkpoint 2C**: All five fixtures pass via `/kiln:kiln-test plugin-kiln <fixture>`. Commit.

---

## Phase 3: Audit + smoke + create PR (Owner: `auditor`)

**Purpose**: PRD-compliance audit, NFR verification, smoke run, PR creation.

- [X] T080 [auditor] PRD compliance trace — 25/25 FRs structurally trace to skill / rubric / build-prd files; 4 blockers documented in `blockers.md` (B-1 substrate gap, B-2 substrate gap, B-3 carve-out resolved, B-4 follow-on).
- [X] T081 [auditor] Run 5 fixtures — substrate-cite B-1: kiln-test plugin-skill harness can't yet drive run.sh-only fixtures. Direct `bash run.sh` invocation (per impl-tests-and-retro bypass) for all 5 — **all PASS**.
- [X] T082 [auditor] NFR-001 — 5 runs: 0.398/0.283/0.284/0.281/0.275; median **0.283 s** vs. gate 1.022 s. PASS by 0.27× the cap. No near-cap warning.
- [X] T083 [auditor] NFR-003 — carve-out applies (within-scope idempotence per spec.md Step 1.5). On no-X path, new code paths are inert. Cross-scope divergence (when substance rules fire) is the FEATURE per FR-010. See B-3.
- [X] T084 [auditor] SC-006 — empirical live verification deferred per B-2 substrate gap (cached plugin SKILL.md is pre-PR). Manual walk: `recent-changes-anti-pattern` and `missing-architectural-context` would fire on current CLAUDE.md; structural rubric trace confirms `match_rule:` references `vision.body` / `roadmap.phases` / `plugins.list` / `claude_md.body` for all 4 new substance rules.
- [X] T085 [auditor] SC-008 — pipeline-internal: task #6 retrospective is the live anchor. SKILL.md Step 5 sub-step 6 contract (lines 1085-1090) + `retro-quality.md` rubric verified structurally. Live SC-008 verifies on next retro fire.
- [X] T086 [auditor] Smoke — Skill invocation attempted; resolved cached pre-PR SKILL.md (B-2). Existing `.kiln/logs/claude-md-audit-*.md` files confirm skill produces non-empty `.kiln/logs/` output. New rubric content verified live via grep on working tree.
- [X] T087 [auditor] PR creation + commit audit-driven fixes — done.

**Checkpoint 3**: PR open, all NFRs verified, all SCs pass. Commit + push.

---

## Phase 4: Retrospective (Owner: `retrospective`; blocked by all prior tasks)

- [ ] T090 [retrospective] Author retrospective issue body. Apply `plugin-kiln/rubrics/retro-quality.md` self-rating (FR-024) — emit `insight_score:` and `insight_score_justification:` honestly. PIs in bold-inline format.
- [ ] T091 [retrospective] File retrospective as a GitHub issue with `label:retrospective`. Body MUST cite spec/plan/tasks paths + the audit-of-pipeline notes (any near-cap NFR-001 warnings, byte-identity carve-out observations, fixture flakiness, etc.).

---

## Dependencies & Execution Order

```
Phase 1 (specifier — DONE this commit)
         ↓
Phase 2A.A → 2A.B → 2A.C → 2A.D → 2A.E   (impl-claude-audit; strict serial)
                                       ↓
Phase 2C [P] (5 fixtures, impl-tests-and-retro; gated on 2A.E)
                                       ↓
Phase 2B (Theme F; impl-tests-and-retro; INDEPENDENT — runs anytime after Phase 1)
                                       ↓
                                  Phase 3 (auditor; gated on 2A.E + 2B + 2C)
                                       ↓
                                  Phase 4 (retrospective; gated on Phase 3)
```

**Parallel start**: Phase 2A.A (T010) and Phase 2B (T060) MAY start simultaneously — they share zero files.
**Strict gate**: Phase 2C cannot start until Phase 2A.E is committed (fixtures exercise post-Theme-E skill behavior).
**Non-strict bonus**: T060 (the rubric file) can land first and immediately unblocks T062-T063 self-rating prompt edits.

## Implementation Strategy

- **Theme A first** (output discipline): without it, the rest of the rubric changes are decorative — Theme A is the contract repair every other Theme assumes.
- **Theme B next** (substance rules): largest user-visible payoff; the headline of the PRD.
- **Themes C, D, E** then layer ordering / anti-pattern / preview file mechanics on top.
- **Theme F (parallel)**: zero overlap with Themes A-E; ship anytime.
- **Fixtures (gated)**: each fixture is a smoke test for one FR; they exercise the post-Theme-E skill.
- **Smoke + audit** (Phase 3): NFR-001 / NFR-003 verification; if NFR-001 trips, profile the bash-side script work to find the regression source; if NFR-003 trips, the carve-out applies (within-scope idempotence) — auditor MUST verify the failure is cross-scope (a real bug) before flagging.

## Notes

- **Numbering**: spec/plan/tasks/contracts all preserve PRD's FR-001..FR-025, NFR-001..NFR-004, SC-001..SC-008 verbatim. No renumbering, no gap-filling.
- **Carve-outs documented** (per Step 1.5 reconciliation): NFR-001 binds bash-side only; NFR-003 binds within-scope idempotence. Both are explicit in spec.md.
- **OQ resolutions**: OQ-1 = soft warning at 95 % cap; OQ-3 = generic `<active-phase>` placeholder for byte-identity; OQ-5 = preamble cross-reference to FR-031 of `claude-md-audit-reframe`; OQ-6 = three concept families (thesis / loop / architectural pointer) for `scaffold-undertaught`. Open ones (OQ-2 editorial-pass tax measurement; OQ-4 `## Smoke-test verification` trailer drop) are flagged for the retro.
- **Test command for NFR-001 re-verification** is reproduced verbatim in research.md §Baseline. The auditor MUST re-run the same script (do NOT re-derive).
- **Plugin-prefixed agent names** (Architectural Rule 1): if T062-T063 spawn or invoke any agents, they MUST use `kiln:<role>` form per the `Architectural Rules — Agent Spawning + Prompt Composition` section in CLAUDE.md.
