---
description: "Task list for merge-pr-and-sc-grep-guidance feature implementation"
---

# Tasks: Merge-PR Skill + Spec-Template SC-Grep Guidance

**Input**: `specs/merge-pr-and-sc-grep-guidance/spec.md`, `specs/merge-pr-and-sc-grep-guidance/plan.md`, `specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md`
**Prerequisites**: spec.md (FR-001..FR-016, NFR-001..NFR-005, SC-001..SC-007), plan.md, contracts/interfaces.md.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel — different files, no dependencies.
- **[Story]**: Maps to spec User Story (US1..US5).
- File paths are exact and absolute under repo root.

## Implementer Assignment (FIXED — concurrent-staging hazard, NFR-005)

- **`impl-roadmap-and-merge`** owns Section [A: roadmap-and-merge] (Phases 1, 3, 4, 5, 6, 7). Sequential within owner.
- **`impl-docs`** owns Section [B: docs] (Phases 2, 8, 9, 10). Independent of Section [A]; phases inside Section [B] may run in parallel.
- Both implementers start in parallel after their respective setup phases complete.
- Each implementer reads ONLY its own section. The two file sets are disjoint (per plan.md and NFR-005).

---

# [A: roadmap-and-merge]

> **Owner**: `impl-roadmap-and-merge` (Theme A — `/kiln:kiln-merge-pr` skill, shared helper, Step 4b.5 refactor, `--check --fix`).
> **Files**: `plugin-kiln/skills/kiln-merge-pr/SKILL.md` (NEW), `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` (NEW), `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 4b.5 refactor), `plugin-kiln/skills/kiln-roadmap/SKILL.md` (`--check --fix` extension), `plugin-kiln/tests/auto-flip-on-merge-fixture/` (NEW fixture + golden files).
> **DO NOT TOUCH**: `plugin-kiln/templates/spec-template.md`, `plugin-wheel/lib/preprocess.sh`, `plugin-wheel/README.md` (impl-docs scope), AND `plugin-kiln/.claude-plugin/plugin.json` (kiln auto-discovers skills from `skills/` — manifest has no `skills` array; team-lead confirmed no edit needed).

## Phase 1: Setup — impl-roadmap-and-merge

**Purpose**: Read spec + plan + contracts before any edit. No code edits yet.

- [ ] T001 [impl-roadmap-and-merge] Read `.specify/memory/constitution.md`, `specs/merge-pr-and-sc-grep-guidance/spec.md`, `specs/merge-pr-and-sc-grep-guidance/plan.md`, `specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md` end-to-end before any edit.
- [ ] T002 [impl-roadmap-and-merge] Verify `git status` is clean on `build/merge-pr-and-sc-grep-guidance-20260427`. If dirty, stop and message team-lead.
- [ ] T003 [impl-roadmap-and-merge] Read `plugin-kiln/skills/kiln-build-prd/SKILL.md` lines ~1019–1132 (the Step 4b.5 inline block + invariants) to internalize the verbatim semantics required for FR-008/FR-009/NFR-002.

---

## Phase 3: User Story 2 — Helper extraction (P1) — impl-roadmap-and-merge

**Goal**: Extract Step 4b.5 inline Bash into `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` and prove byte-identity via golden-file fixture.
**Independent Test**: `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` returns PASS.

### Implementation

- [ ] T010 [impl-roadmap-and-merge] [US2] Create `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` per `contracts/interfaces.md` §A.1. Body is a verbatim transcription of Step 4b.5's Bash block, modulo positional argument parsing (`PR_NUMBER="${1:-}"`, `PRD_PATH="${2:-}"` with usage-error handling) and a `read_derived_from()` helper inlined or sourced. Add header comment citing FR-008/FR-009/NFR-002.
- [ ] T011 [impl-roadmap-and-merge] [US2] Run `chmod +x plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`. Confirm shebang line is `#!/usr/bin/env bash` (matches `update-item-state.sh`).
- [ ] T012 [impl-roadmap-and-merge] [US2] Spot-test the helper manually: invoke with `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh 999 /nonexistent/path` → expect non-zero exit with usage error. Invoke with valid args but `gh` returning non-MERGED → expect `auto-flip=skipped reason=pr-not-merged`.

### Test for User Story 2

- [ ] T013 [impl-roadmap-and-merge] [US2] Capture pre/post-merge snapshots from commit `22a91b10`: for each of the three `derived_from:` items in `docs/features/2026-04-26-escalation-audit/PRD.md`, run `git show 22a91b10^:.kiln/roadmap/items/<item>.md > plugin-kiln/tests/auto-flip-on-merge-fixture/golden/pre/<item>.md` and `git show 22a91b10:.kiln/roadmap/items/<item>.md > plugin-kiln/tests/auto-flip-on-merge-fixture/golden/post/<item>.md`. Capture `git show 22a91b10:docs/features/2026-04-26-escalation-audit/PRD.md > plugin-kiln/tests/auto-flip-on-merge-fixture/golden/prd.md`.
- [ ] T013a [impl-roadmap-and-merge] [US2] **Date-stability substitution (SC-002 / NFR-002)**: in each captured `golden/post/<item>.md`, replace the literal date string in the `shipped_date:` line (likely `shipped_date: 2026-04-26`) with the placeholder `shipped_date: <TODAY>`. Do NOT modify the `pr:` field. The placeholder is the test-time substitution target; the helper still emits today's actual UTC date and the fixture's `run.sh` substitutes the placeholder with `date -u +%Y-%m-%d` before the byte-for-byte `diff`. This keeps the helper a verbatim extraction (NFR-002) AND keeps the fixture stable across days.
- [ ] T014 [impl-roadmap-and-merge] [US2] Create `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` per `contracts/interfaces.md` §G.2. Cite SC-002 in header. Make executable. **Per T013a**: before each `diff`, materialize a comparison file by running `sed "s/<TODAY>/$(date -u +%Y-%m-%d)/g" "$HERE/golden/post/<item>.md" > "$TMP/expected/<item>.md"` and diff against that materialized file (NOT the raw golden). The `<TODAY>` placeholder MUST be substituted in the expected snapshot, never written into the helper-mutated item.
- [ ] T015 [impl-roadmap-and-merge] [US2] Run the fixture from repo root: `bash plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh`. Assert it prints `PASS`. If it fails, fix the helper until both the post-flip diff AND the idempotent-re-run diff pass. Confirm PASS on a second invocation later in the day (or by stubbing `date` differently) to verify the `<TODAY>` substitution works.

### Checkpoint — Commit Phase 3

- [ ] T016 [impl-roadmap-and-merge] [US2] Stage by exact path: `git add plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh plugin-kiln/tests/auto-flip-on-merge-fixture/golden/`. Commit: `feat(roadmap): extract Step 4b.5 auto-flip block to shared helper (FR-008, NFR-002)`.

---

## Phase 4: User Story 2 — Step 4b.5 refactor (P1) — impl-roadmap-and-merge

**Goal**: Replace the inline Step 4b.5 Bash block with a single-line helper invocation. Zero behavior change (NFR-002).
**Independent Test**: Re-running the auto-flip-on-merge-fixture against the refactored skill body still passes (the helper itself is unchanged); SC-003 visual check passes.

### Implementation

- [ ] T020 [impl-roadmap-and-merge] [US2] In `plugin-kiln/skills/kiln-build-prd/SKILL.md`, locate Step 4b.5 (heading at line ~1019). Replace ONLY the bash code-fence body (the ~80-line block from `# FR-003 — gate on PR merge state` to the closing `echo "step4b-auto-flip: ..."` line) with the two-line replacement from `contracts/interfaces.md` §A.3 (one comment + one helper invocation). Preserve the `### Step 4b.5: ...` heading, **Purpose**/**When this runs**/**Inputs** prose, **Diagnostic line literal**/**Verification regex** code-fences, and **Step 4b.5 invariants** list verbatim.
- [ ] T021 [impl-roadmap-and-merge] [US2] Verify `wc -l plugin-kiln/skills/kiln-build-prd/SKILL.md` strictly decreased compared to pre-edit baseline (SC-003).
- [ ] T022 [impl-roadmap-and-merge] [US2] Re-run `bash plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh`. Assert PASS (helper is the unit under test; this confirms no regression from the refactor's accompanying edits).
- [ ] T023 [impl-roadmap-and-merge] [US2] Re-run the existing `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` (escalation-audit's fixture). If its extract pattern still parses against the refactored SKILL.md, it MUST still pass. If the extract pattern broke because the inline block is gone, document the substitution in the test fixture or update its assertion to source the helper directly. Note any update in `agent-notes/impl-roadmap-and-merge.md`.

### Checkpoint — Commit Phase 4

- [ ] T024 [impl-roadmap-and-merge] [US2] Stage by exact path: `git add plugin-kiln/skills/kiln-build-prd/SKILL.md` (and any updated existing fixture file from T023). Commit: `refactor(build-prd): step 4b.5 calls shared auto-flip-on-merge.sh helper (FR-009, SC-003)`.

---

## Phase 5: User Story 1 — `/kiln:kiln-merge-pr` skill (P1, MVP) — impl-roadmap-and-merge

**Goal**: Ship the new skill that maintainer invokes instead of `gh pr merge`.
**Independent Test**: Live-fire SC-001 closes on this PRD's own PR; structural-test below verifies skill body parses.

### Implementation

- [ ] T030 [impl-roadmap-and-merge] [US1] Create `plugin-kiln/skills/kiln-merge-pr/SKILL.md` per `contracts/interfaces.md` §B.1, §B.2. Frontmatter (name + description) per §B.1. Body sections: Purpose, Inputs, Stages 1–6 with the diagnostic-line literals, Idempotency notes, Working-tree-dirty rule, Helper invocation contract.
- [ ] T031 [impl-roadmap-and-merge] [US1] In Stage 1 (preflight), use `git status --porcelain` to detect dirty tree; refuse with the canonical exit-2 diagnostic line. NEVER `git stash` automatically (PRD R-3, V1).
- [ ] T032 [impl-roadmap-and-merge] [US1] In Stage 2 (mergeability gate), accept either `state=OPEN` AND `mergeStateStatus ∈ {CLEAN, MERGEABLE}`, OR `state=MERGED` (idempotent skip path per FR-002a, NFR-001). Refuse all other combinations.
- [ ] T033 [impl-roadmap-and-merge] [US1] In Stage 3 (merge), `gh pr merge <pr> --<method> --delete-branch`. Method default `--squash` per FR-001. Wait for `gh pr view <pr> --json state` to return `MERGED` before proceeding (FR-003).
- [ ] T034 [impl-roadmap-and-merge] [US1] In Stage 4 (PRD location), `gh pr view <pr> --json files`, lex-sort, take `[0]` matching `docs/features/*/PRD.md` (FR-004). On zero matches, emit `kiln-merge-pr: pr=<n> auto-flip=skipped reason=no-prd-in-changeset` and exit 0.
- [ ] T035 [impl-roadmap-and-merge] [US1] In Stage 5 (auto-flip), invoke `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh <pr> <prd-path>` (FR-005). Under `--no-flip`, skip Stage 5 entirely with diagnostic `kiln-merge-pr: pr=<n> auto-flip=skipped reason=--no-flip` (FR-007).
- [ ] T036 [impl-roadmap-and-merge] [US1] In Stage 6 (commit + push), use the FR-006/§B.3 staging contract: derive flipped paths from the helper (Approach 1: re-walk derived_from + `git diff --name-only` filter; or Approach 2: helper emits `flipped-path:` lines on stderr). Stage by exact path; NEVER `git add -A`. Commit with `chore(roadmap): auto-flip on merge of PR #<n>`. Push to `origin`. If zero files mutated, emit `result=skipped-no-changes` and don't commit.
- [ ] T037 [impl-roadmap-and-merge] [US1] **REMOVED per team-lead correction** — kiln plugin uses filesystem auto-discovery from `skills/`. `plugin-kiln/.claude-plugin/plugin.json` has only `workflows` + `agent_bindings` arrays — no `skills` array. Creating `plugin-kiln/skills/kiln-merge-pr/SKILL.md` is sufficient registration. **Do NOT touch the manifest.** Mark this task completed as a no-op confirmation only.

### Test for User Story 1 (structural)

- [ ] T038 [impl-roadmap-and-merge] [US1] Run `grep -c '^### Stage' plugin-kiln/skills/kiln-merge-pr/SKILL.md` — expect ≥ 6 (one per stage). Run `grep -F 'kiln-merge-pr: pr=' plugin-kiln/skills/kiln-merge-pr/SKILL.md` — expect ≥ 5 hits (one per stage diagnostic).
- [ ] T039 [impl-roadmap-and-merge] [US1] Run `grep -F '--no-flip' plugin-kiln/skills/kiln-merge-pr/SKILL.md` — expect ≥ 2 hits (flag declaration + skip-stage logic). Run `grep -F 'auto-flip-on-merge.sh' plugin-kiln/skills/kiln-merge-pr/SKILL.md` — expect ≥ 1 hit (helper invocation).
- [ ] T040 [impl-roadmap-and-merge] [US1] Run `grep -F 'git add -A' plugin-kiln/skills/kiln-merge-pr/SKILL.md` — MUST return zero hits (NFR-005 invariant).

### Checkpoint — Commit Phase 5

- [ ] T041 [impl-roadmap-and-merge] [US1] Stage by exact path: `git add plugin-kiln/skills/kiln-merge-pr/SKILL.md`. (Per T037: do NOT add `plugin-kiln/.claude-plugin/plugin.json` — manifest is not edited.) Commit: `feat(merge-pr): add /kiln:kiln-merge-pr skill — atomic merge + auto-flip (FR-001..FR-007, NFR-001)`.

---

## Phase 6: User Story 3 — `--check --fix` (P2) — impl-roadmap-and-merge

**Goal**: Extend `/kiln:kiln-roadmap --check` with `--fix` confirm-never-silent mode.
**Independent Test**: Structural grep + a manual scenario walkthrough (drift synthesis → invoke → accept → assert flipped → invoke → skip → assert no diff).

### Implementation

- [ ] T050 [impl-roadmap-and-merge] [US3] In `plugin-kiln/skills/kiln-roadmap/SKILL.md` §C, after the existing Check 5 report assembly, add a `--fix` mode block per `contracts/interfaces.md` §C.2. Gate the entire block behind a `--fix` flag check; without `--fix`, behavior MUST be byte-identical (NFR-004 backward-compat).
- [ ] T051 [impl-roadmap-and-merge] [US3] In the `--fix` block, prompt `[fix all / pick / skip]` confirm-never-silent. Treat empty input as `skip` (NFR-004). Print the per-entry helper output as it runs.
- [ ] T052 [impl-roadmap-and-merge] [US3] Resolve PR per drifted item via `gh pr list --state merged --search "head:<feature-branch>"` (FR-011). On zero or multiple matches, mark `[ambiguous]` and skip THAT item; never guess.
- [ ] T053 [impl-roadmap-and-merge] [US3] Emit final summary line `fix=success items=<N> patched=<K> already_shipped=<S> ambiguous=<A>` per §C.3.
- [ ] T054 [impl-roadmap-and-merge] [US3] Document the new flag in the skill's frontmatter description AND in the existing `--check` synopsis at the top of the SKILL.md.

### Test for User Story 3 (structural)

- [ ] T055 [impl-roadmap-and-merge] [US3] Run `grep -F 'fix all / pick / skip' plugin-kiln/skills/kiln-roadmap/SKILL.md` — expect ≥ 1 hit. Run `grep -F 'auto-flip-on-merge.sh' plugin-kiln/skills/kiln-roadmap/SKILL.md` — expect ≥ 1 hit. Run `grep -F 'ambiguous' plugin-kiln/skills/kiln-roadmap/SKILL.md` — expect ≥ 1 hit.
- [ ] T056 [impl-roadmap-and-merge] [US3] Manually walk the scenario: pick a known-shipped item, revert its `state` field to `distilled` and strip `pr:` + `shipped_date:` (in a scratch branch or via `git restore`). Run `/kiln:kiln-roadmap --check --fix`, respond `skip`, assert `git diff` empty. Run again, respond `accept`, assert the item flipped back. Restore the original state via `git checkout`.

### Checkpoint — Commit Phase 6

- [ ] T057 [impl-roadmap-and-merge] [US3] Stage by exact path: `git add plugin-kiln/skills/kiln-roadmap/SKILL.md`. Commit: `feat(roadmap): --check --fix confirm-never-silent drift fixer (FR-010, FR-011)`.

---

## Phase 7: Friction note + handoff — impl-roadmap-and-merge

- [ ] T060 [impl-roadmap-and-merge] Write `specs/merge-pr-and-sc-grep-guidance/agent-notes/impl-roadmap-and-merge.md` with: ambiguities encountered, deviations from contract (with justifications), prompt-clarity issues, anything that surprised you mid-implementation. Required for retrospective.
- [ ] T061 [impl-roadmap-and-merge] Stage by exact path: `git add specs/merge-pr-and-sc-grep-guidance/agent-notes/impl-roadmap-and-merge.md`. Commit: `chore(specs): impl-roadmap-and-merge friction note`.
- [ ] T062 [impl-roadmap-and-merge] SendMessage to `team-lead` and to `audit-traceability` + `audit-tests`: "Theme A complete — 6 commits, files: kiln-merge-pr/SKILL.md, auto-flip-on-merge.sh, build-prd/SKILL.md (refactor), kiln-roadmap/SKILL.md (--fix), tests/auto-flip-on-merge-fixture/. SC-002 fixture passes; SC-003 wc-l decreased; SC-004 manual scenario passed. Ready for audit." Mark task #2 completed.

---

# [B: docs]

> **Owner**: `impl-docs` (Themes B + C — spec-template SC-grep recipe, wheel preprocess + README documentary-references rule).
> **Files**: `plugin-kiln/templates/spec-template.md`, `plugin-wheel/lib/preprocess.sh`, `plugin-wheel/README.md`.
> **DO NOT TOUCH**: any file under `plugin-kiln/skills/`, `plugin-kiln/scripts/`, `plugin-kiln/tests/`, `plugin-kiln/.claude-plugin/`. Those belong to `impl-roadmap-and-merge` (and the manifest is not edited at all per team-lead confirmation).

## Phase 2: Setup — impl-docs [P with Phase 1]

- [ ] T070 [impl-docs] Read `.specify/memory/constitution.md`, `specs/merge-pr-and-sc-grep-guidance/spec.md`, `specs/merge-pr-and-sc-grep-guidance/plan.md`, `specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md` (focus on §D, §E, §F) end-to-end before any edit.
- [ ] T071 [impl-docs] Read `plugin-kiln/templates/spec-template.md`, `plugin-wheel/lib/preprocess.sh`, `plugin-wheel/README.md` end-to-end to internalize current structure (none of these files have been touched yet for this PRD).

---

## Phase 8: User Story 4 — Spec-template SC-grep recipe (P2) — impl-docs

**Goal**: Append the date-bound SC-grep authoring note + recipe to `plugin-kiln/templates/spec-template.md`'s Success Criteria section.
**Independent Test**: SC-005 grep assertions return matches.

### Implementation

- [X] T080 [impl-docs] [US4] Open `plugin-kiln/templates/spec-template.md`. Locate the `## Success Criteria *(mandatory)*` section. Append after the existing `### Measurable Outcomes` subsection (and its example bullets) the canonical authoring-note block from `contracts/interfaces.md` §D.2 verbatim.
- [X] T081 [impl-docs] [US4] Verify the literal string `date-bound qualifier` appears in the new block. Verify the recipe code-fence contains `--since='YYYY-MM-DD'`. Verify the substantive-alternative paragraph (FR-013) is present.

### Test for User Story 4

- [X] T082 [impl-docs] [US4] Run `grep -F 'date-bound qualifier' plugin-kiln/templates/spec-template.md` — expect ≥ 1 match. Run `grep -F "--since='YYYY-MM-DD'" plugin-kiln/templates/spec-template.md` — expect ≥ 1 match. SC-005 sentinels.

### Checkpoint — Commit Phase 8

- [X] T083 [impl-docs] [US4] Stage by exact path: `git add plugin-kiln/templates/spec-template.md`. Commit: `docs(spec-template): SC-grep date-bound authoring note + recipe (FR-012, FR-013)`.

---

## Phase 9: User Story 5 — Wheel preprocess module-comment + tripwire error (P2) — impl-docs

**Goal**: Add module-level documentary-references comment to `plugin-wheel/lib/preprocess.sh` and extend the FR-F4-5 tripwire error text.
**Independent Test**: SC-006 grep + tripwire-output assertion.

### Implementation

- [ ] T090 [impl-docs] [US5] Open `plugin-wheel/lib/preprocess.sh`. Append the module-level comment block from `contracts/interfaces.md` §E.1 verbatim, IMMEDIATELY AFTER the existing module header (around line ~62 — after the substitution-stages narrative, before the function definitions). The literal word `documentary` MUST appear.
- [ ] T091 [impl-docs] [US5] Locate the FR-F4-5 tripwire emit (around line ~177; the `printf` that emits the residual-token report immediately before `exit 1`). Extend its rendered output by APPENDING a new line containing the canonical sentence from `contracts/interfaces.md` §E.2: `If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.`. Preferred form is the longer sentence; if a concrete consumer requires shorter, use the §E.3 condensed form (the literal "documentary" sentinel survives both).
- [ ] T092 [impl-docs] [US5] Trace a small synthetic input through the tripwire mentally to confirm the new line is part of the rendered stderr (NOT swallowed by a missing newline or shell-quoting bug).

### Test for User Story 5 (preprocess)

- [ ] T093 [impl-docs] [US5] Run `grep -F 'documentary' plugin-wheel/lib/preprocess.sh` — expect ≥ 1 match. Run `grep -F 'rewrite as plain prose' plugin-wheel/lib/preprocess.sh` — expect ≥ 1 match (the FR-016 tripwire-error sentinel).
- [ ] T094 [impl-docs] [US5] If a unit-style test for the tripwire output exists or can easily be written, add a one-line assertion that the tripwire's stderr contains `If you intended this as documentary text` for a synthesized residual-token input. Acceptable to defer — note the deferral in friction note T100 if so.

### Checkpoint — Commit Phase 9 (partial)

- [ ] T095 [impl-docs] [US5] Stage by exact path: `git add plugin-wheel/lib/preprocess.sh`. Commit: `docs(wheel/preprocess): module comment + tripwire error documentary-references rule (FR-014, FR-016)`.

---

## Phase 10: User Story 5 — Wheel README authoring section (P2) — impl-docs

**Goal**: Add `## Writing agent instructions` section to `plugin-wheel/README.md`.
**Independent Test**: SC-006 grep on README.

### Implementation

- [ ] T096 [impl-docs] [US5] Open `plugin-wheel/README.md`. Add a new top-level heading `## Writing agent instructions` after the `## Workflow Format` section's field-table + step-types subsection (READMe currently 293 lines; placement near the end is acceptable per plan §2). Body is the canonical block from `contracts/interfaces.md` §F.2 verbatim (or with light prose framing — the literal `documentary` sentinel and the bulleted ✅/❌ examples MUST be present).
- [ ] T097 [impl-docs] [US5] Verify the new heading is reachable from the README's heading hierarchy (any reasonable markdown reader will find it). If the README has a TOC at the top, add the new heading to it.

### Test for User Story 5 (README)

- [ ] T098 [impl-docs] [US5] Run `grep -F 'documentary' plugin-wheel/README.md` — expect ≥ 1 match. Run `grep -F 'Writing agent instructions' plugin-wheel/README.md` — expect ≥ 1 match (the heading itself).
- [ ] T099 [impl-docs] [US5] Run the cumulative SC-006 assertion: `grep -lF 'documentary' plugin-wheel/lib/preprocess.sh plugin-wheel/README.md` — expect BOTH paths in output.

### Checkpoint — Commit Phase 10

- [ ] T100 [impl-docs] [US5] Stage by exact path: `git add plugin-wheel/README.md`. Commit: `docs(wheel/README): Writing agent instructions section — documentary references rule (FR-015)`.

---

## Phase 10b: Friction note + handoff — impl-docs

- [ ] T101 [impl-docs] Write `specs/merge-pr-and-sc-grep-guidance/agent-notes/impl-docs.md` with: ambiguities encountered, deviations from contract (with justifications), prompt-clarity issues, anything that surprised you mid-implementation. Required for retrospective.
- [ ] T102 [impl-docs] Stage by exact path: `git add specs/merge-pr-and-sc-grep-guidance/agent-notes/impl-docs.md`. Commit: `chore(specs): impl-docs friction note`.
- [ ] T103 [impl-docs] SendMessage to `team-lead` and to `audit-traceability` + `audit-tests`: "Themes B + C complete — 4 commits, files: spec-template.md, preprocess.sh, README.md. SC-005 + SC-006 sentinels asserted via grep. Ready for audit." Mark task #3 completed.

---

# Dependencies & Concurrency

- Phase 1 + Phase 2 are setup-only (no edits) → start in parallel.
- Phase 3 (helper extraction) MUST complete before Phase 4 (Step 4b.5 refactor uses the helper).
- Phase 4 + Phase 5 + Phase 6 are sequential within `impl-roadmap-and-merge` (all touch `plugin-kiln/skills/...` plus shared state from Phase 3).
- Phase 8 + Phase 9 + Phase 10 inside `impl-docs` are independent (different files) and may run in any order or in parallel within the implementer.
- Section [A] and Section [B] run in parallel from setup onward — file sets are disjoint per NFR-005.

# Cumulative SC mapping

| SC | Validated by | Phase / Task |
|----|--------------|--------------|
| SC-001 | Live-fire on this PRD's own PR (audit-pr stage) | Acceptance Test |
| SC-002 | `auto-flip-on-merge-fixture/run.sh` PASS | Phase 3 / T015 |
| SC-003 | `wc -l` strictly decreased + grep diff inspection | Phase 4 / T021 |
| SC-004 | Manual scenario walkthrough | Phase 6 / T056 |
| SC-005 | `grep -F 'date-bound qualifier' ...` + recipe-fence grep | Phase 8 / T082 |
| SC-006 | `grep -lF 'documentary' ...` (both files) + tripwire-error grep | Phase 9 / T093 + Phase 10 / T098–T099 |
| SC-007 | Re-run `/kiln:kiln-merge-pr` on this PRD's merged PR (audit-pr stage) | Acceptance Test |
