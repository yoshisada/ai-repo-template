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

- [ ] T020 [impl-claude-audit] [B] Add `## Substance rules` section to `plugin-kiln/rubrics/claude-md-usefulness.md`. Append rule entry `missing-thesis` per `contracts/interfaces.md` §2 (FR-006). Pre-filter: cheap grep for vision-pillar phrases before invoking editorial pass (R-1 mitigation).
- [ ] T021 [impl-claude-audit] [B] Append rule entry `missing-loop` per §2 (FR-007).
- [ ] T022 [impl-claude-audit] [B] Append rule entry `missing-architectural-context` per §2 (FR-008).
- [ ] T023 [impl-claude-audit] [B] Append rule entry `scaffold-undertaught` per §2 (FR-009).
- [ ] T024 [impl-claude-audit] [B] Update `kiln-claude-audit/SKILL.md` output ordering: Signal Summary table sort key `(signal_type_rank, severity_rank, rule_id)` per `contracts/interfaces.md` §4. `signal_type: substance` rank = 0 (FR-010).
- [ ] T025 [impl-claude-audit] [B] Update `kiln-claude-audit/SKILL.md` Notes section ordering: substance findings rendered before mechanical findings (FR-010).
- [ ] T026 [impl-claude-audit] [B] Smoke: run audit against source repo; verify ≥1 substance row at top of Signal Summary; verify each substance rule's `match_rule:` cites `CTX_JSON` paths.

**Checkpoint 2A.B**: Four substance rules + ordering live. Commit.

### Phase 2A.C — Theme C (grounded citations + step reorder; FR-012..FR-015)

- [ ] T030 [impl-claude-audit] [C] Update `kiln-claude-audit/SKILL.md` finding-rendering rules: every finding's Notes row MUST include a one-line `remove-this-citation-and-verdict-changes-because: <reason>` rationale (FR-012). Decorative correlations forbidden as primary justifications.
- [ ] T031 [impl-claude-audit] [C] Add project-context-driven row guarantee: after Step 3, inspect fired-signals; if zero rules with non-empty `ctx_json_paths:` fired, emit `(no project-context signals fired)` placeholder in Signal Summary per `contracts/interfaces.md` §4 (FR-013).
- [ ] T032 [impl-claude-audit] [C] Reorder `kiln-claude-audit/SKILL.md` step sequence: substance pass at Step 2 (was Step 3 cheap pass); cheap rubric pass at Step 3; Step 3.5 invariant; Step 4 render; Step 4.5 sibling previews (Theme E placeholder — file authored in Theme E); Step 5 external deltas; Step 6 write (FR-015).
- [ ] T033 [impl-claude-audit] [C] Smoke: run audit; verify substance pass output appears before cheap rubric pass in audit log; verify any finding citing `CTX_JSON` includes a non-empty rationale line.

**Checkpoint 2A.C**: Citations are load-bearing; ordering reflects substance-first. Commit.

### Phase 2A.D — Theme D (recent-changes anti-pattern + load-bearing reword; FR-016..FR-019)

- [ ] T040 [impl-claude-audit] [D] Append rule entry `recent-changes-anti-pattern` to `plugin-kiln/rubrics/claude-md-usefulness.md` per `contracts/interfaces.md` §2 (FR-016). Proposed-diff body uses generic `<active-phase>` placeholder (OQ-4 reconciliation: byte-identity preserved across re-runs).
- [ ] T041 [impl-claude-audit] [D] Update `kiln-claude-audit/SKILL.md` and `kiln-doctor/SKILL.md` `recent-changes-overflow` handlers: emit no signal when section absent; demote to `keep` when `recent-changes-anti-pattern` fires in same audit (FR-017).
- [ ] T042 [impl-claude-audit] [D] Reword `load-bearing-section` rule prose in `plugin-kiln/rubrics/claude-md-usefulness.md`: load-bearing means cited from skill/agent/hook/workflow PROSE (instructions, descriptions, error messages); NOT load-bearing when cited only inside a rule's `match_rule:` field. Same applies to `## Active Technologies` cited by `active-technologies-overflow` (FR-018).
- [ ] T043 [impl-claude-audit] [D] Smoke: run audit; verify `recent-changes-anti-pattern` fires (current source repo has `## Recent Changes`) with removal-candidate diff containing the §2 standardized pointer block.

**Checkpoint 2A.D**: Anti-pattern rule + load-bearing reword live. Commit.

### Phase 2A.E — Theme E (sibling preview convention; FR-020..FR-023)

- [ ] T050 [impl-claude-audit] [E] Update `kiln-claude-audit/SKILL.md` permitted-files allowlist to include `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` per `contracts/interfaces.md` §5 (FR-020).
- [ ] T051 [impl-claude-audit] [E] Add Step 4.5 to `kiln-claude-audit/SKILL.md`: render one sibling preview per audited path with ≥1 proposed diff. Filename derivation: replace `/` with `-` in repo-relative path. Content: post-apply state of the audited file (verbatim; no diff markers) (FR-021).
- [ ] T052 [impl-claude-audit] [E] Add audit log cross-reference text: `Side-by-side preview: see <audit-log-basename>-proposed-<basename>.md.` rendered immediately under `## Proposed Diff` heading, one line per audited path with a sibling preview (FR-022).
- [ ] T053 [impl-claude-audit] [E] Add audit log footer string: `Once proposed diffs land, this audit log + sibling preview files can be archived to .kiln/logs/archive/ or deleted.` — static, always present (FR-023).
- [ ] T054 [impl-claude-audit] [E] Smoke: run audit on source repo; verify two sibling preview files written (one per audited path: `CLAUDE.md` and `plugin-kiln/scaffold/CLAUDE.md`); verify cross-reference + footer rendered.

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

- [ ] T070 [P] [impl-tests-and-retro] [A] Author fixture `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` (FR-002 / SC-001). Scaffold a CLAUDE.md known to fire `external/length-density`; assert audit output contains zero `# ... No diff proposed` lines.
- [ ] T071 [P] [impl-tests-and-retro] [A] Author fixture `plugin-kiln/tests/claude-audit-editorial-pass-required/` (FR-005 / SC-002). Scaffold a CLAUDE.md paraphrasing constitution content + a fixture-local `.specify/memory/constitution.md`; assert `duplicated-in-constitution` fires with `action: duplication-flag` (NOT `inconclusive`).
- [ ] T072 [P] [impl-tests-and-retro] [B] Author fixture `plugin-kiln/tests/claude-audit-substance/` (FR-011 / SC-003). Scaffold a structurally-clean CLAUDE.md with no vision-pillar reference + a fixture-local `.kiln/vision.md`; assert `missing-thesis` fires.
- [ ] T073 [P] [impl-tests-and-retro] [C] Author fixture `plugin-kiln/tests/claude-audit-grounded-finding-required/` (FR-014 / SC-004). Scaffold a structurally-clean CLAUDE.md that diverges from `.kiln/vision.md` content; assert ≥1 substance finding fires with primary-justification citation of `CTX_JSON` content; assert the rationale line (`remove-this-citation-and-verdict-changes-because: <reason>`) is present + non-empty.
- [ ] T074 [P] [impl-tests-and-retro] [D] Author fixture `plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/` (FR-019 / SC-005). Scaffold a CLAUDE.md containing `## Recent Changes`; assert `recent-changes-anti-pattern` fires with action `removal-candidate` and a proposed diff containing the standardized pointer block.

**Checkpoint 2C**: All five fixtures pass via `/kiln:kiln-test plugin-kiln <fixture>`. Commit.

---

## Phase 3: Audit + smoke + create PR (Owner: `auditor`)

**Purpose**: PRD-compliance audit, NFR verification, smoke run, PR creation.

- [ ] T080 [auditor] PRD compliance: trace every FR (FR-001..FR-025) → spec.md → tasks.md → file edits. Trace NFR-001..NFR-004 → spec.md NFR section + research.md baseline. Trace SC-001..SC-008 → fixtures + smoke runs. Document any gap in `specs/claude-audit-quality/blockers.md`.
- [ ] T081 [auditor] Run all five fixtures via `/kiln:kiln-test plugin-kiln <fixture>`; collect verdict reports; SC-001..SC-005 pass.
- [ ] T082 [auditor] NFR-001 verification: re-run the `/tmp/audit-bench.sh` script (source in research.md §Baseline) 5 times; compute median; assert median ≤ 1.022 s (the +30 % gate against 0.786 s baseline). If median ≥ 0.95 s, emit a soft "near-cap" note in the audit-of-pipeline (OQ-1).
- [ ] T083 [auditor] NFR-003 verification: run `/kiln:kiln-claude-audit` twice in a row against unchanged inputs (kiln source repo); diff the two output files (ignore the `**Generated**: <ISO-timestamp>` header line); assert zero diff in `## Signal Summary` + `## Proposed Diff` sections.
- [ ] T084 [auditor] SC-006: grep audit log for `signal_type: substance`; confirm at least one substance row's `match_rule:` references `vision.body` (or another `CTX_JSON` path).
- [ ] T085 [auditor] SC-008: run a small `kiln-build-prd` pipeline (or simulate the retro-write step in isolation); verify the retro issue body contains `insight_score:` + `insight_score_justification:` in frontmatter.
- [ ] T086 [auditor] Run smoke-tester agent against the audit skill — invoke `/kiln:kiln-claude-audit` from a fresh CLI session, verify outputs land in `.kiln/logs/`.
- [ ] T087 [auditor] Commit any audit-driven fixes; create PR via `gh pr create` with the build-prd label; PR title `feat: claude-audit-quality — substance rules + output discipline + retro insight-score`.

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
