# Tasks: PRD `derived_from:` Frontmatter

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)
**Implementer count**: 1 (single implementer owns all tasks)
**Total tasks**: 13

Tasks are partitioned into 6 phases (A, B, C, D, E, F). Implementer MUST mark each `[X]` immediately on completion and commit once per phase.

---

## Phase A — Distill writer: emit `derived_from:` frontmatter + FR-002 invariant (FR-001, FR-002, FR-003)

- [X] **T01-1** Add the YAML frontmatter emit step to `plugin-kiln/skills/kiln-distill/SKILL.md` Step 4.
  - Insert the frontmatter block (contracts §1.1) BEFORE the existing `# Feature PRD: <Theme Name>` heading in the PRD body template (SKILL.md lines ~128–186).
  - Key order MUST match contracts §1.2 — `derived_from:`, `distilled_date:`, `theme:`.
  - `distilled_date` value is produced by `date -u +%Y-%m-%d` (plan.md Decision D2).
  - `theme` value is the slug portion of the PRD directory basename (`<date>-<slug>` → `<slug>`).
  - List-item format matches contracts §1.3 (two-space indent + `- ` + unquoted repo-relative path).
  - Sort order matches contracts §1.4 (feedback first; filename ASC within each group).
  - Validation: after distill runs against a fixture with 1 feedback + 1 issue, `head -6 <PRD>` shows `---`, `derived_from:`, `  - .kiln/feedback/...`, `  - .kiln/issues/...`, `distilled_date: <YYYY-MM-DD>`, `theme: <slug>`, `---`.
  - **Maps to**: FR-001, FR-003.
  - **Files**: `plugin-kiln/skills/kiln-distill/SKILL.md`.

- [X] **T01-2** Render the `### Source Issues` body table from the SAME in-memory list (FR-002 invariant) and add the drift-abort check.
  - The frontmatter `derived_from:` list and the body table MUST be produced from a single in-memory array (see contracts §1.6 pseudocode).
  - The drift-abort assertion (at write time) compares `derived_from:` paths against the table's first-column paths in order; mismatch → exit non-zero with a clear error message. No partial PRD is emitted.
  - Empty-list case (contracts §1.5) MUST emit `derived_from: []` on a single line; also emits an empty Source Issues table (or omits the table section) consistently — whichever shape the assertion can handle.
  - Validation: after distill, `FRONTMATTER_PATHS="$(awk ...frontmatter extractor...)"; TABLE_PATHS="$(awk ...table extractor...)"; test "$FRONTMATTER_PATHS" = "$TABLE_PATHS"` returns 0. (See SMOKE.md §5.1 assertion block.)
  - **Maps to**: FR-002.
  - **Files**: `plugin-kiln/skills/kiln-distill/SKILL.md`.

**Phase A commit**: `feat(kiln-distill): write derived_from frontmatter on generated PRDs (FR-001, FR-002, FR-003)`

---

## Phase B — Build-prd Step 4b: frontmatter-path reader + extended diagnostic (FR-004, FR-005, FR-006)

- [ ] **T02-1** Add the `read_derived_from()` helper to `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b.
  - Paste the awk-state-machine extractor from contracts §2.1 verbatim.
  - Helper reads ONLY the first `---`…`---` block; bails on the first non-`---` line before any `---`.
  - Emits zero lines on missing / malformed / empty frontmatter (falls through to scan-fallback on zero output).
  - Validation: `grep -F 'read_derived_from()' plugin-kiln/skills/kiln-build-prd/SKILL.md` matches; unit-check by feeding fixture PRDs (frontmatter-present, frontmatter-absent, malformed block) to the helper and asserting the expected output.
  - **Maps to**: FR-004 (reader input), FR-005 (fallback trigger on empty output).
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

- [ ] **T02-2** Add the frontmatter-path archive loop + `missing_entries` tracking.
  - Paste contracts §2.2 (branch decision) + §2.3 (frontmatter-path archive loop) verbatim.
  - On the frontmatter path, `SCANNED_ISSUES` and `SCANNED_FEEDBACK` are incremented from the `derived_from:` list (NOT a directory scan).
  - Missing entries are accumulated into `MISSING_ENTRIES` but do NOT stop the loop (FR-006).
  - On the scan-fallback path (contracts §2.4), `MISSING_ENTRIES=()` is initialized empty BEFORE the PR-#146 loop runs; the PR-#146 loop stays unchanged.
  - Validation: `grep -F 'MISSING_ENTRIES+=("$entry")' plugin-kiln/skills/kiln-build-prd/SKILL.md` matches; SMOKE.md §5.2 sub-fixture A prints `OK`.
  - **Maps to**: FR-004, FR-005, FR-006.
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

- [ ] **T02-3** Replace the diagnostic-line composition with the extended 8-field version.
  - Paste contracts §2.5 verbatim — `MISSING_JSON` computed via `jq -Rn '[inputs]' -c`; `DIAG_LINE=` appends `derived_from_source=` and `missing_entries=` AFTER the existing `prd_path=${PRD_PATH_NORM}` field.
  - DO NOT reorder / rename / remove any existing field. Fields 1–6 MUST match the PR-#146 grep regex (contracts §2.6.2).
  - Validation: on a frontmatter-path run, the diagnostic line matches both the extended regex (contracts §2.6.1) AND the PR-#146 regex (contracts §2.6.2). SMOKE.md §5.2 sub-fixture A AND B both print `OK`.
  - **Maps to**: FR-006, NFR-005.
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

**Phase B commit**: `feat(kiln-build-prd): step 4b reads derived_from frontmatter + extended diagnostic (FR-004, FR-005, FR-006)`

---

## Phase C — Hygiene rule: frontmatter-walk primary + fallback + rubric text (FR-007, FR-008)

- [ ] **T03-1** Add the frontmatter-walk primary path to `plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 5c.
  - Insert the contracts §3.1 block BEFORE the existing walk-backlog loop (SKILL.md ~line 215).
  - Declare `declare -A PROCESSED_PRDS` near the top of Step 5c (after `declare -A MERGED_BY_SLUG`).
  - Reuse the same `read_derived_from()` helper shape (contracts §2.1); if the hygiene skill doesn't already have it, paste it into a sourceable location (either inline in Step 5c OR shared between build-prd and hygiene — implementer's choice, but MUST live under `plugin-kiln/` to satisfy NFR-002).
  - Emit one signal per `derived_from:` entry using the same `archive-candidate` / `needs-review` / `inconclusive` taxonomy as today.
  - Validation: `grep -F 'PROCESSED_PRDS' plugin-kiln/skills/kiln-hygiene/SKILL.md` matches; SMOKE.md §5.3 mixed-state assertion prints `OK`.
  - **Maps to**: FR-007.
  - **Files**: `plugin-kiln/skills/kiln-hygiene/SKILL.md`.

- [ ] **T03-2** Narrow the walk-backlog fallback and update the rubric.
  - Add the `PROCESSED_PRDS` skip predicate to the existing walk-backlog loop (contracts §3.2) — each per-file iteration checks `[ -n "${PROCESSED_PRDS[$prd_path]:-}" ] && continue` after reading `prd_path`.
  - Validate: output for pre-migration PRDs (no `derived_from:`) is byte-identical to today's output. Diff against a pre-change golden fixture OR run `SMOKE.md §5.3` with an unmigrated-only PRD and compare signals.
  - Update `plugin-kiln/rubrics/structural-hygiene.md` — insert the contracts §3.3 paragraph into the `merged-prd-not-archived` rule narrative (between the "Fires against..." list and the "Bulk-lookup strategy" paragraph).
  - Validation: `grep -F 'Primary path (post PRD `derived_from:`' plugin-kiln/rubrics/structural-hygiene.md` matches.
  - **Maps to**: FR-008, NFR-001.
  - **Files**: `plugin-kiln/skills/kiln-hygiene/SKILL.md`, `plugin-kiln/rubrics/structural-hygiene.md`.

**Phase C commit**: `feat(kiln-hygiene): merged-prd-not-archived reads derived_from primary + fallback (FR-007, FR-008)`

---

## Phase D — Migration subcommand: `/kiln:kiln-hygiene backfill` (FR-009, FR-010, FR-011)

- [ ] **T04-1** Add the `backfill` subcommand dispatcher to `plugin-kiln/skills/kiln-hygiene/SKILL.md`.
  - Paste contracts §4.1 at the top of the skill's main execution block (after any pre-execution hook checks).
  - The default (no-subcommand) path runs today's full structural hygiene audit unchanged.
  - Unknown subcommand → exit 2 with a `Known subcommands:` error line.
  - Validation: `/kiln:kiln-hygiene` (no args) behaves as today; `/kiln:kiln-hygiene backfill` enters the backfill branch; `/kiln:kiln-hygiene unknown` exits 2.
  - **Maps to**: FR-009 (entry point).
  - **Files**: `plugin-kiln/skills/kiln-hygiene/SKILL.md`.

- [ ] **T04-2** Implement the backfill workflow body (per-PRD diff hunk composer).
  - Paste contracts §4.2 verbatim.
  - Idempotence predicate (contracts §4.2 `head -20 ... grep -Eq '^derived_from:'`) MUST match both the non-empty list case AND the empty-list case (`derived_from: []`) — both treated as already-migrated (FR-010, Decision D3).
  - Source Issues table parser extracts the `](<path>)` markdown-link target from each data row; sort feedback-first then issues (contracts §4.2 `derived_lines` block).
  - Path-validation: rows whose path does not exist on disk are emitted as commented-out hunks (`+  # - <path>  # path does not exist on disk — review`).
  - `distilled_date:` derives from the PRD body's `**Date**: <YYYY-MM-DD>` line; falls back to `date -u -r <file> +%Y-%m-%d` with an inline `# distilled_date inferred from file mtime — review` comment annotation (plan.md Decision D2).
  - Validation: run on a fixture PRD missing `derived_from:` — preview file exists, contains 1 hunk; re-run on the same state (with the hunk applied to the fixture) — preview contains `0 items`. SMOKE.md §5.3 assertion prints `OK`.
  - **Maps to**: FR-009, FR-010, FR-011.
  - **Files**: `plugin-kiln/skills/kiln-hygiene/SKILL.md`.

- [ ] **T04-3** Add the rubric entry for the backfill rule + the CLAUDE.md command entry.
  - Append contracts §4.3 (a new `### derived_from-backfill` block) to `plugin-kiln/rubrics/structural-hygiene.md` AFTER the `### merged-prd-not-archived` section and BEFORE `### orphaned-top-level-folder`.
  - Add one line to `CLAUDE.md` under the "### QA (two workflows — same 4-agent team…)" or "Other" section in the "Available Commands" list — specifically under "Other" since hygiene lives there: `- \`/kiln:kiln-hygiene backfill\` — One-shot propose-don't-apply backfill of PRD \`derived_from:\` frontmatter. Writes preview at \`.kiln/logs/prd-derived-from-backfill-<timestamp>.md\`. Idempotent — safe to re-run.`
  - Validation: `grep -F 'rule_id: derived_from-backfill' plugin-kiln/rubrics/structural-hygiene.md` matches; `grep -F '/kiln:kiln-hygiene backfill' CLAUDE.md` matches.
  - **Maps to**: FR-009 (rubric + discoverability).
  - **Files**: `plugin-kiln/rubrics/structural-hygiene.md`, `CLAUDE.md`.

**Phase D commit**: `feat(kiln-hygiene): add backfill subcommand for derived_from migration (FR-009, FR-010, FR-011)`

---

## Phase E — Smoke fixtures + SMOKE.md (SC-008)

- [ ] **T05-1** Author the distill + Step 4b sections of `specs/prd-derived-from-frontmatter/SMOKE.md`.
  - §5.1 (Distill writer fixture, SC-001, SC-006) — copy contracts §5.1 verbatim, add a brief introduction and "How to run" block.
  - §5.2 (Step 4b extended diagnostic fixture, SC-002, SC-003, SC-007 replay) — copy contracts §5.2 verbatim, including BOTH sub-fixtures (A: frontmatter path; B: scan-fallback). Document the PR-#146 regex replay check inline.
  - Each fixture MUST end with an explicit `echo OK || echo FAIL` line.
  - **Maps to**: SC-001, SC-002, SC-003, SC-006, SC-008.
  - **Files**: `specs/prd-derived-from-frontmatter/SMOKE.md`.

- [ ] **T05-2** Author the hygiene + migration section of `SMOKE.md`.
  - §5.3 (Hygiene + migration fixture, SC-004, SC-005) — copy contracts §5.3 verbatim.
  - Include both mixed-state hygiene assertions AND the twice-run idempotence assertion (second invocation emits `0 items`).
  - Add a caveat that the fixture uses a stubbed `gh` call (implementer picks the simulation approach — either a shim script or a pre-populated `MERGED_BY_SLUG` fixture).
  - **Maps to**: SC-004, SC-005, SC-008.
  - **Files**: `specs/prd-derived-from-frontmatter/SMOKE.md`.

**Phase E commit**: `docs(spec): add SMOKE.md fixtures for prd-derived-from-frontmatter (SC-008)`

---

## Phase F — Backwards-compat verification (NFR-001, NFR-005, SC-007)

- [ ] **T06-1** Run SC-007 end-to-end and log the result in `specs/prd-derived-from-frontmatter/agent-notes/implementer.md`.
  - Target PRD: `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` (pre-migration; no `derived_from:`).
  - In a verification sandbox (branch or scratch worktree — DO NOT commit the verification run's state to the feature branch), run `/kiln:kiln-build-prd` against the target PRD (or manually trigger Step 4b with the appropriate `$PRD_PATH` + `$PR_NUMBER`).
  - Capture the diagnostic line from stdout AND from `.kiln/logs/build-prd-step4b-<TODAY>.md`.
  - Apply `specs/pipeline-input-completeness/SMOKE.md` §5.3's exact grep regex against the captured line — confirm it STILL matches (contracts §2.6.2).
  - Confirm `derived_from_source=scan-fallback` and `missing_entries=[]` appear on the line.
  - Document:
    1. The full captured diagnostic line.
    2. The PR-#146 regex and whether it matched (`OK` / `FAIL`).
    3. The extended regex from contracts §2.6.1 and whether it matched.
    4. Any unexpected behavior.
  - If any grep check FAILs, the implementer MUST stop and open a debugger loop BEFORE marking T06-1 complete.
  - **Maps to**: NFR-001, NFR-005, SC-007.
  - **Files**: `specs/prd-derived-from-frontmatter/agent-notes/implementer.md`.

**Phase F commit**: `chore(spec): backwards-compat verification log for prd-derived-from-frontmatter (NFR-001, NFR-005, SC-007)`

---

## Friction Notes (NON-NEGOTIABLE)

Each agent MUST write `specs/prd-derived-from-frontmatter/agent-notes/<agent-name>.md` BEFORE marking its top-level task `completed`. The retrospective reads these notes instead of polling live agents.

Per-agent notes:

- `specifier.md` — written by the specifier now (before completing Task #1).
- `implementer.md` — written by the implementer at the end of Phase F (also carries the T06-1 verification log).
- `auditor.md` — written by the auditor before opening the PR.

## Completion Definition

This task list is fully `[X]` when:

1. All 13 tasks above are marked `[X]`.
2. `grep -F 'derived_from_source=' plugin-kiln/skills/kiln-build-prd/SKILL.md` returns at least one match (the extended diagnostic template appears in the SKILL body).
3. `grep -F 'derived_from:' plugin-kiln/skills/kiln-distill/SKILL.md` returns at least one match (the writer step is present).
4. `grep -F 'PROCESSED_PRDS' plugin-kiln/skills/kiln-hygiene/SKILL.md` returns at least one match (the frontmatter-walk primary path is present).
5. `grep -F 'rule_id: derived_from-backfill' plugin-kiln/rubrics/structural-hygiene.md` returns at least one match (the new rubric entry is present).
6. `specs/prd-derived-from-frontmatter/SMOKE.md` exists with §5.1, §5.2, and §5.3 fixture sections.
7. `specs/prd-derived-from-frontmatter/agent-notes/implementer.md` exists with the Phase F verification log.
8. The implementer has committed once per phase (6 commits expected — A, B, C, D, E, F).
