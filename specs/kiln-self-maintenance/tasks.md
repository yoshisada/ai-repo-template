---

description: "Task breakdown for kiln-self-maintenance feature"
---

# Tasks: Kiln Self-Maintenance

**Input**: `specs/kiln-self-maintenance/` (spec.md, plan.md, contracts/interfaces.md)
**Prerequisites**: all spec artifacts committed

## Owners

- **impl-claude-audit** — owns Phases R, S, T, V and part of W. Files: `plugin-kiln/rubrics/claude-md-usefulness.md`, `plugin-kiln/skills/kiln-claude-audit/SKILL.md`, `plugin-kiln/skills/kiln-doctor/SKILL.md`, `plugin-kiln/scaffold/CLAUDE.md`, plus Phase V edits to `CLAUDE.md` (source repo).
- **impl-feedback-interview** — owns Phase U and part of W. Files: `plugin-kiln/skills/kiln-feedback/SKILL.md`.

Each implementer marks `[X]` immediately on task completion. Commit after each phase.

## Format: `[ID] [P?] [Owner] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Owner]**: Who is responsible

---

## Phase R — Research + Rubric artifact (FR-002, FR-003)

**Purpose**: Ground the audit mechanism in a versioned rubric before any skill writes a line.

- [X] T001 [impl-claude-audit] Inventory CLAUDE.md references by grepping `plugin-*/skills/`, `plugin-*/agents/`, `plugin-*/hooks/`, `plugin-*/workflows/`, and `templates/` for section headers + phrase citations. Record the load-bearing set in `specs/kiln-self-maintenance/agent-notes/phase-r-inventory.md` (scratch; not shipped).
- [X] T002 [impl-claude-audit] Create `plugin-kiln/rubrics/claude-md-usefulness.md` with preamble + the 7 required rule entries listed in `contracts/interfaces.md` §1, using the per-entry field shape. Include the 3 configurable thresholds with their defaults.
- [X] T003 [impl-claude-audit] Self-check: grep the rubric path from at least one non-skill location in the repo (spec.md already references it — confirm NFR-004 with `grep -rn plugin-kiln/rubrics/claude-md-usefulness.md specs/ plugin-*/ docs/` and record the hit count in the phase-r notes).

**Checkpoint**: rubric exists, is discoverable, conforms to §1 schema. Commit "feat(kiln): claude-md usefulness rubric (Phase R)".

---

## Phase S — Audit skill + kiln-doctor integration (FR-001, FR-004, FR-005)

**Purpose**: Land the dedicated `/kiln:kiln-claude-audit` skill and the cheap doctor subcheck. Depends on R (rubric must exist to be read).

- [ ] T004 [impl-claude-audit] Create `plugin-kiln/skills/kiln-claude-audit/SKILL.md` with frontmatter (`name: kiln-claude-audit`, description). Implement Steps per contract §2: (1) resolve RUBRIC_PATH and CLAUDE_MD_PATH (including scaffold audit when in source repo, FR-005), (2) load + merge optional `.kiln/claude-md-audit.config` (contract §7), (3) run every rubric rule (cheap + editorial), (4) write `.kiln/logs/claude-md-audit-<timestamp>.md` per §2 shape. Include the no-drift marker line.
- [ ] T005 [impl-claude-audit] Implement the editorial signal handler in the new skill: agent-step that reads CLAUDE.md + docs/PRD.md + constitution.md, returns duplication/staleness findings. Match the pattern already used by `/kiln:kiln-audit`. On LLM failure, mark the signal `inconclusive` in the diff (edge case in spec).
- [ ] T006 [impl-claude-audit] Implement override-parser helper inline in the skill body: plain key-value line parser (`=` or `:`), warn-and-fallback on malformed, warn-and-ignore on unknown rule_id (Decision 1).
- [ ] T007 [impl-claude-audit] Add CLAUDE.md subcheck to `plugin-kiln/skills/kiln-doctor/SKILL.md`: new Step 3g that runs ONLY cheap-cost rubric rules, appends one row to the diagnosis table per contract §3 (format: `| CLAUDE.md drift | OK|DRIFT | <details> |`). Resolve the rubric path via the same logic doctor uses for the manifest. Performance budget <2s.
- [ ] T008 [impl-claude-audit] Idempotency check (NFR-002): run the audit skill twice against an unchanged fixture CLAUDE.md. Diff-body and Signal-Summary table must be byte-identical between the two outputs (timestamps allowed to differ). Record the verification in `specs/kiln-self-maintenance/agent-notes/phase-s-idempotency.md`.
- [ ] T009 [impl-claude-audit] SC-001 fixture test: create a minimal CLAUDE.md that should pass the rubric, run the audit, confirm the output file's header reads `**Result**: no drift` and the diff body is empty. Record result in phase-s notes.

**Checkpoint**: audit skill runs clean on fixture, drifts on dirty input, doctor subcheck completes <2s, idempotency holds. Commit "feat(kiln): /kiln:kiln-claude-audit skill + kiln-doctor subcheck (Phase S)".

---

## Phase T — Scaffold rewrite (FR-006, SC-003) [parallel with S]

**Purpose**: One-time rewrite of the consumer-repo scaffold to the minimal skeleton shape.

- [ ] T010 [impl-claude-audit] Rewrite `plugin-kiln/scaffold/CLAUDE.md` from scratch per `contracts/interfaces.md` §4 exact skeleton. Target ≤40 lines. Remove the explicitly-excluded sections listed in §4.
- [ ] T011 [impl-claude-audit] Verify: run the new audit skill against the new scaffold, confirm an empty-diff output (§4 audit-clean verification). If drift appears, either adjust the skeleton or adjust the rubric (update contracts/interfaces.md FIRST per plan Decision 3 / constitution VII).
- [ ] T012 [impl-claude-audit] Verify SC-003: `git diff --stat plugin-kiln/scaffold/CLAUDE.md` shows >50% of original lines changed. Record the stat in `specs/kiln-self-maintenance/agent-notes/phase-t-rewrite.md`.

**Checkpoint**: scaffold rewritten, audit-clean, SC-003 satisfied. Commit "feat(kiln): rewrite plugin-kiln/scaffold/CLAUDE.md as minimal skeleton (Phase T)".

---

## Phase U — Feedback interview mode (FR-007..FR-010) [parallel with A-track]

**Purpose**: Extend `/kiln:kiln-feedback` with the inline interview between the classification gate and the file write. Fully independent of Phases R/S/T.

- [X] T013 [impl-feedback-interview] Edit `plugin-kiln/skills/kiln-feedback/SKILL.md`: insert Step 4a "Offer Skip" and Step 4b "Interview" between existing Step 4 (Classify) and Step 5 (Write). Preserve all existing steps and the NFR-003 contracts (no wheel, no MCP, no background sync).
- [X] T014 [impl-feedback-interview] Implement the 3 default questions in Step 4b using the exact wording from `contracts/interfaces.md` §5 table. Implement the last-option-skip (exact wording `skip interview — just capture the one-liner`) at every prompt.
- [X] T015 [impl-feedback-interview] Implement the area → add-on dispatcher in Step 4b: read the `area` value classified in Step 4, look up the Qa/Qb wording from the §5 area map, ask them in order. For area `other`, skip add-ons (total = 3 questions).
- [X] T016 [impl-feedback-interview] Implement blank-answer handling per §5: re-prompt once on empty input; write `(no answer)` on the second blank. Implement mid-interview skip semantics per Decision 5: skip at ANY prompt drops all partial answers and proceeds with no `## Interview` section.
- [X] T017 [impl-feedback-interview] Extend Step 5 to write the `## Interview` body section per `contracts/interfaces.md` §6 when the interview completed, or omit the section entirely on skip. Frontmatter stays byte-identical to today (NFR-003). Verify SC-005, SC-006, SC-007 by scripted invocation; record results in `specs/kiln-self-maintenance/agent-notes/phase-u-verify.md`.

**Checkpoint**: feedback skill runs the interview by default, captures answers in the body, honors the skip option. Commit "feat(kiln): /kiln:kiln-feedback interview mode (Phase U)".

---

## Phase V — First audit pass + accepted edits (FR-011, SC-002, SC-008)

**Purpose**: Prove the mechanism on real accumulated bloat and commit the pruning in the same PR.

- [ ] T018 [impl-claude-audit] Run `/kiln:kiln-claude-audit` against the current source-repo `CLAUDE.md` (and the freshly-rewritten scaffold — which should be clean). Review the resulting `.kiln/logs/claude-md-audit-<timestamp>.md`. Confirm it flags at least: (a) the speckit-harness → kiln Migration Notice, (b) Recent-Changes entries beyond the rubric's `recent_changes_keep_last_n` threshold, (c) at least one section duplicated vs. docs/PRD.md or the constitution (SC-002).
- [ ] T019 [impl-claude-audit] Apply non-controversial edits from the audit diff to the source-repo `CLAUDE.md`. "Non-controversial" = the three SC-002 categories plus any other high-confidence removals the diff marked. Leave editorial LLM calls that were marked `inconclusive` untouched — those go into the phase-v notes for later human review.
- [ ] T020 [impl-claude-audit] Commit the CLAUDE.md edits (SC-008). Save the audit log under `.kiln/logs/` (keep it — this is the baseline). Record accepted/deferred signals in `specs/kiln-self-maintenance/agent-notes/phase-v-first-pass.md`.

**Checkpoint**: SC-002 and SC-008 satisfied; first-pass commit present. Commit "chore(claude-md): apply first audit pass pruning (Phase V)".

---

## Phase W — Smoke results + handoff docs

**Purpose**: Summarize the verification results so downstream audit / PR review doesn't have to re-run every SC.

- [ ] T021 [last-lander] Create `specs/kiln-self-maintenance/SMOKE.md` summarizing SC-001..SC-008 results with pointers to the phase notes (`agent-notes/phase-r-inventory.md`, `phase-s-idempotency.md`, `phase-t-rewrite.md`, `phase-u-verify.md`, `phase-v-first-pass.md`) and the first-pass audit log path. One-liner per SC: `PASS | FAIL | DEFERRED` with a single-line rationale. `last-lander` = whichever implementer finishes their phase last (impl-claude-audit after Phase V, or impl-feedback-interview after Phase U — whoever is later).

**Checkpoint**: SMOKE.md committed. Commit "docs(spec): SMOKE.md — kiln-self-maintenance verification results (Phase W)".

---

## Dependencies & Execution Order

### Phase dependencies

- **R** — no deps. Starts first.
- **S** — depends on R (reads rubric).
- **T** — depends on R (reads rubric for audit-clean check at T011). Parallelizable with S (different files: rubric + audit skill + doctor subcheck vs. scaffold file).
- **U** — independent. Starts immediately in parallel with R/S/T.
- **V** — depends on S (needs audit skill) and T (needs the scaffold audit-clean baseline).
- **W** — depends on R, S, T, U, V (last-lander writes SMOKE.md summarizing all SCs).

### Owner partition

- **impl-claude-audit** (≈15 tasks): T001–T012, T018–T020 = 15 tasks. Plus co-authors T021 if they finish last.
- **impl-feedback-interview** (≈5 tasks): T013–T017 = 5 tasks. Plus co-authors T021 if they finish last.
- **Total**: 21 tasks — matches target cap.

### Parallel opportunities

- Phase U runs fully in parallel with Phases R+S+T+V (different file owner).
- Phase T can start as soon as Phase R completes (before S finishes), in parallel with Phase S.

## Notes

- Each implementer commits per-phase, not at the end.
- If a task fails, leave it `[ ]` and document the failure in the phase notes before moving on.
- Phase V's "non-controversial" judgement call is explicitly a human-reviewed step — the audit skill does not auto-apply (FR-004). The implementer is the human reviewer for Phase V.
- If Phase V's first pass finds that the rubric is too strict (too many false-positive signals), the fix is to update the rubric (contracts/interfaces.md §1 first, then the rubric file) and re-run — NOT to skip signals.
- SMOKE.md in Phase W is the handoff artifact for the auditor agent. It must reference every SC by ID so the auditor can check traceability without re-running smoke tests.
