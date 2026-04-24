# Feature Spec: PRD `derived_from:` Frontmatter

**Feature slug**: `prd-derived-from-frontmatter`
**Branch**: `build/prd-derived-from-frontmatter-20260424`
**Parent PRD**: [docs/features/2026-04-24-prd-derived-from-frontmatter/PRD.md](../../docs/features/2026-04-24-prd-derived-from-frontmatter/PRD.md)
**Status**: Draft
**Date**: 2026-04-24

## Summary

Every PRD under `docs/features/` is derived from one or more `.kiln/issues/` or `.kiln/feedback/` source files, but that derivation is written only as a human-readable `### Source Issues` markdown table in the PRD body. The reverse direction (item → PRD) is machine-readable via the `prd:` frontmatter key on every source item; the forward direction (PRD → items) is not. Two pipeline-critical consumers (`/kiln:kiln-build-prd` Step 4b and `/kiln:kiln-hygiene`'s `merged-prd-not-archived` rule) currently invert that edge by scanning every backlog file and string-matching the `prd:` field — the exact pattern PR #146 just shipped a path-normalization fix for.

This spec adds `derived_from:` YAML frontmatter to every PRD produced by `/kiln:kiln-distill`, switches both consumers to a read-PRD-once primary path, keeps the PR-#146 scan-and-match fallback for pre-migration PRDs, and ships a propose-don't-apply backfill that retrofits the frontmatter onto existing PRDs.

## Inherited Context

From `CLAUDE.md`:

- This is the **plugin source repo** for `@yoshisada/kiln`. `src/` and `tests/` do not exist here — they are scaffolded into consumer projects. This spec edits **plugin sources** (`plugin-kiln/skills/kiln-distill/`, `plugin-kiln/skills/kiln-build-prd/`, `plugin-kiln/skills/kiln-hygiene/`, `plugin-kiln/rubrics/structural-hygiene.md`), not `src/`.
- The plugin workflow portability invariant applies: any shell scripts referenced from workflow command steps MUST resolve via `${WORKFLOW_PLUGIN_DIR}/scripts/...` — never via repo-relative `plugin-<name>/scripts/...`. This spec introduces NO workflow command-step scripts (all changes live in SKILL.md bodies or rubric markdown), so the invariant is trivially satisfied; any future refactor that moves logic into a helper script MUST honor it.
- Diagnostic output goes to `.kiln/logs/` with `keep_last: 10` retention (kiln-manifest rule). The migration's preview output (`.kiln/logs/prd-derived-from-backfill-<timestamp>.md`) inherits that retention with no additional config.
- Propose-don't-apply is the discipline for audits that touch many files at once: `/kiln:kiln-claude-audit` and `/kiln:kiln-hygiene` both write review previews under `.kiln/logs/` and never call `Edit`/`Write` on the audited files. This spec's migration tool adopts the same discipline (plan.md Decision 1 selects the entry point).

From `.specify/memory/constitution.md`:

- Article I (Spec-First) — this spec is the gate before edits.
- Article III (PRD as Source of Truth) — the parent PRD drives scope; every FR/NFR/SC in this spec maps to a PRD FR/NFR/SC. Deviations from the PRD are captured as locked Decisions in plan.md.
- Article VI (Small, Focused Changes) — three reader edits + one writer edit + one propose-don't-apply migration. No premature abstraction; the frontmatter schema stays tiny (3 keys), the diagnostic extension stays additive (2 fields).
- Article VII (Interface Contracts) — `contracts/interfaces.md` pins the frontmatter block shape, key order, path rules, extended Step 4b diagnostic schema, and the migration diff preview layout verbatim.
- Article VIII (Incremental Task Completion) — tasks ship across 6 phases (A, B, C, D, E, F); commit per phase.

From the PRD's "Risks & Open Questions": three open questions that plan.md locks as Decisions D1–D3.

## Current State (verified by reading the source)

**`/kiln:kiln-distill` Step 4 (PRD generator)** — `plugin-kiln/skills/kiln-distill/SKILL.md`, lines 100–189. The PRD body template (lines 128–186) declares front-of-body metadata (`**Date**`, `**Status**`, `**Parent PRD**`), the `### Source Issues` table (lines 141–147), then the usual narrative sections. There is NO YAML frontmatter block at the top of the generated PRD — the `**Date**: YYYY-MM-DD` line lives inside the markdown body. Step 5 ("Update Source Status") already handles the reverse edge (`.kiln/issues/*.md` and `.kiln/feedback/*.md` get `status: prd-created` + `prd: <path>`), but writes nothing back to the PRD.

**`/kiln:kiln-build-prd` Step 4b** — `plugin-kiln/skills/kiln-build-prd/SKILL.md`, lines 590–722. Post PR #146, Step 4b scans `.kiln/issues/*.md` AND `.kiln/feedback/*.md`, normalizes paths, archives matched items, and emits a 6-field diagnostic line:

```
step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<A> skipped=<S> prd_path=<PRD_PATH>
```

The diagnostic literal is grep-anchored by the SMOKE.md fixture at `specs/pipeline-input-completeness/SMOKE.md` §5.3. No `derived_from:` awareness. No `missing_entries` surfacing.

**`/kiln:kiln-hygiene` `merged-prd-not-archived` rule** — `plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 5c, lines 174–253. Walks `.kiln/issues/*.md` AND `.kiln/feedback/*.md`, reads each file's `status:` + `prd:` frontmatter, derives the PRD's feature-slug from the `prd:` dirname, and compares against a bulk `gh pr list --state merged` map. Emits `archive-candidate` / `needs-review` / `inconclusive` per item. No `derived_from:` awareness either.

**`plugin-kiln/rubrics/structural-hygiene.md`** — the `merged-prd-not-archived` rule definition (lines 23–48). Describes the walk-backlog-and-match pattern as today's contract; this spec's Phase C updates the rule text to describe the new read-PRD-once primary path plus the walk-backlog fallback.

**Existing PRDs under `docs/features/`** — ~20 PRD.md files, none with `derived_from:` frontmatter (verified by reading two recent samples: `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` and `docs/features/2026-04-24-prd-derived-from-frontmatter/PRD.md`). Each carries the `### Source Issues` body table introduced by distill; the table rows reference `.kiln/issues/…` and `.kiln/feedback/…` paths in the first column. These tables are the migration's input source.

## User Stories

### US-001 — Distill writes a machine-readable source list (FR-001, FR-002, FR-003)

**As** a maintainer running `/kiln:kiln-distill` to bundle open backlog into a feature PRD,
**I want** the generated PRD to carry `derived_from:`, `distilled_date:`, and `theme:` in YAML frontmatter at the top of the file,
**so that** every downstream consumer can iterate the source list without re-parsing the body markdown.

- **Given** open items `.kiln/feedback/a.md` and `.kiln/issues/b.md` are both selected into a new PRD,
  **When** `/kiln:kiln-distill` writes `docs/features/2026-04-30-theme/PRD.md`,
  **Then** the file begins with a YAML frontmatter block whose keys appear in the exact order
  `derived_from:`, `distilled_date:`, `theme:`,
  **And** `derived_from:` lists `.kiln/feedback/a.md` BEFORE `.kiln/issues/b.md` (FR-012 ordering),
  **And** every path is repo-relative with forward slashes,
  **And** the `### Source Issues` body table lists the same two rows in the same order.

### US-002 — Build-prd Step 4b reads the PRD once (FR-004, FR-005, FR-006)

**As** a maintainer running `/kiln:kiln-build-prd` on a PRD that already carries `derived_from:`,
**I want** Step 4b to read the PRD's frontmatter and iterate the list instead of string-matching across every backlog file,
**so that** the lifecycle flip is deterministic and the matched-count invariant always equals the list length.

- **Given** a PRD at `$PRD_PATH` carries `derived_from: [.kiln/feedback/a.md, .kiln/issues/b.md]` and both files exist on disk with `status: prd-created`,
  **When** Step 4b runs,
  **Then** both files flip to `status: completed`, get `completed_date:` and `pr:` lines, and move into their respective `completed/` subdir,
  **And** the diagnostic line reports `derived_from_source: frontmatter`, `missing_entries: []`, `matched=2`, `archived=2`, `skipped=0`,
  **And** the original 6 fields (`scanned_issues`, `scanned_feedback`, `matched`, `archived`, `skipped`, `prd_path`) still appear unchanged in the same grep-anchored positions so the PR #146 SMOKE.md fixture still passes.

### US-003 — Pre-migration PRDs fall back safely (FR-005, NFR-001, NFR-005)

**As** a maintainer running `/kiln:kiln-build-prd` on a PRD written before this feature shipped,
**I want** Step 4b to fall back to the PR-#146 scan-and-match behavior with no user-visible change,
**so that** in-flight pipelines and unmigrated PRDs keep working.

- **Given** a PRD at `$PRD_PATH` has no YAML frontmatter or has frontmatter missing the `derived_from:` key,
  **When** Step 4b runs,
  **Then** the step runs the PR-#146 scan-and-match loop unchanged,
  **And** the diagnostic line reports `derived_from_source: scan-fallback`, `missing_entries: []`,
  **And** archival, log append, and commit behavior are byte-identical to today's PR-#146 behavior.

### US-004 — Missing-entry guard surfaces drift without aborting (FR-006)

**As** a maintainer debugging a hand-edited PRD whose `derived_from:` references a file that was moved or renamed,
**I want** Step 4b to record the missing entry in the diagnostic, continue archiving the rest, and NOT fail the pipeline,
**so that** partial drift is visible the first time and the pipeline still completes.

- **Given** `derived_from:` lists `.kiln/feedback/a.md` (exists) and `.kiln/feedback/moved.md` (does NOT exist),
  **When** Step 4b runs,
  **Then** `a.md` archives normally,
  **And** the diagnostic line reports `missing_entries: [".kiln/feedback/moved.md"]`, `matched=1`, `archived=1`, `skipped=0`,
  **And** the `matched == len(derived_from)` invariant is explicitly NOT enforced when `missing_entries` is non-empty (per PRD FR-006).

### US-005 — Hygiene reads PRDs instead of walking backlog (FR-007, FR-008)

**As** a maintainer running `/kiln:kiln-hygiene` across a mixed-state repo (some PRDs migrated, some not),
**I want** the `merged-prd-not-archived` rule to prefer each PRD's `derived_from:` list as the primary path, and fall back to walk-backlog for PRDs missing `derived_from:`,
**so that** the audit's signals converge with the pipeline's view of the world and the rule's logic stops duplicating the scan-and-match pattern.

- **Given** a mixed repo with PRD-A (has `derived_from: [...]`) and PRD-B (no `derived_from:`),
  **When** `/kiln:kiln-hygiene` runs,
  **Then** PRD-A produces one signal per entry in its `derived_from:` list (archive-candidate / needs-review / inconclusive per the existing rule semantics),
  **And** PRD-B produces signals via the existing walk-backlog path with byte-identical output to today (NFR-001).

### US-006 — Maintainer backfills existing PRDs in one review pass (FR-009, FR-010, FR-011)

**As** a maintainer with 20+ existing PRDs under `docs/features/`,
**I want** a single invocation that proposes a `derived_from:` backfill for every PRD missing the block,
**so that** I can review and apply one bundled diff instead of retrofitting each PRD by hand.

- **Given** N PRDs under `docs/features/` (and any under `products/<slug>/features/` when present) missing `derived_from:`,
  **When** the maintainer runs the migration entry point (per plan.md Decision 1),
  **Then** a single review preview is written to `.kiln/logs/prd-derived-from-backfill-<timestamp>.md`,
  **And** the preview contains one unified-diff hunk per PRD sorted by PRD path ASC, grouped under a `## Bundled: derived_from-backfill (<N> items)` section,
  **And** PRDs that already carry `derived_from:` produce ZERO hunks (idempotence),
  **And** the migration NEVER calls `Edit`/`Write` on any PRD file (propose-don't-apply).

## Requirements

### Functional Requirements

**Distill-side (writer):**

- **FR-001** `/kiln:kiln-distill` Step 4 MUST write a YAML frontmatter block at the top of every generated PRD file. The block MUST contain exactly three keys in this exact order: `derived_from:`, `distilled_date:`, `theme:`. `derived_from:` is a YAML block sequence (one `  - <path>` per line). `distilled_date:` is a UTC ISO-8601 date (YYYY-MM-DD) — see plan.md Decision D2. `theme:` is the slug of the PRD directory (the portion after the date prefix — e.g. `prd-derived-from-frontmatter` for `docs/features/2026-04-24-prd-derived-from-frontmatter/`). Frontmatter precedes the existing `# Feature PRD: <Theme Name>` heading. (PRD FR-001)

- **FR-002** The `### Source Issues` markdown table in the PRD body MUST be rendered from the same in-memory list that produced `derived_from:`. Same entries, same order. `/kiln:kiln-distill` writes both from a single data structure so they cannot drift at write time. On a distill run where the two disagree, the distill skill MUST abort with an error rather than emit a drifted PRD (invariant check). (PRD FR-002)

- **FR-003** `derived_from:` paths MUST be repo-relative, forward-slashed, and represent the on-disk path of the source file at distill time. Paths are NOT Obsidian paths; they are NOT GitHub URLs. Feedback-source paths (`.kiln/feedback/...`) appear BEFORE issue-source paths (`.kiln/issues/...`) within the list (matches FR-012 ordering from `/kiln:kiln-distill`). Within each source-type group, entries are sorted by filename ASC (stable, deterministic order). (PRD FR-003; NFR-003 idempotence hook)

**Build-prd Step 4b (reader + fallback):**

- **FR-004** `/kiln:kiln-build-prd` Step 4b MUST — on every run — attempt to read the current PRD's YAML frontmatter. If the frontmatter block exists AND contains a `derived_from:` key with a non-empty list, Step 4b takes the **frontmatter path**: it iterates the list directly, flips each listed file's `status:` to `completed`, inserts `completed_date:` + `pr:`, and moves it into the originating directory's `completed/` subdir. No scan-and-match. (PRD FR-004)

- **FR-005** If the PRD has NO frontmatter, or the frontmatter lacks a `derived_from:` key, or `derived_from:` is an empty list, Step 4b falls back to the existing PR-#146 scan-and-match path and its 6-field diagnostic. The scan-fallback path is byte-identical to today's behavior except for the two additive diagnostic fields defined in FR-006. The diagnostic line's new field `derived_from_source:` MUST be set to either the literal string `frontmatter` or the literal string `scan-fallback`. (PRD FR-005, NFR-001, NFR-005)

- **FR-006** On the frontmatter path, for each entry in `derived_from:` the file MUST exist on disk at the stated repo-relative path. If an entry does NOT exist, Step 4b records the missing path in the diagnostic's new `missing_entries:` JSON array field, continues processing the remaining entries, and does NOT fail the pipeline. The diagnostic line's new fields are APPENDED at the end of the line (after the PR-#146 6 fields) so existing grep-anchored patterns still match. The matched-count invariant (`matched == len(derived_from)`) fires ONLY when `missing_entries` is empty; when `missing_entries` is non-empty the invariant is explicitly waived. (PRD FR-006, NFR-005)

**Hygiene `merged-prd-not-archived` rule (reader + fallback):**

- **FR-007** `plugin-kiln/rubrics/structural-hygiene.md`'s `merged-prd-not-archived` rule MUST — as its primary path — read each PRD's `derived_from:` frontmatter and emit one `archive-candidate` / `needs-review` / `inconclusive` signal per entry in the list, using the existing bulk `gh pr list --state merged` map keyed by derived slug. The rule walks PRDs (under `docs/features/*/PRD.md` and `products/*/features/*/PRD.md`), not backlog files, on the primary path. The rubric markdown under `plugin-kiln/rubrics/structural-hygiene.md` is updated to describe the new primary path. (PRD FR-007)

- **FR-008** PRDs without `derived_from:` (pre-migration) continue to be processed by the existing walk-backlog path — the rule falls back to scanning `.kiln/issues/*.md` and `.kiln/feedback/*.md` for any item whose `prd:` frontmatter points at a PRD that lacks `derived_from:`. Output for the fallback path is byte-identical to today's output (identical signal rows, identical sort order, identical bundled-accept section shape). (PRD FR-008, NFR-001)

**Migration (propose-don't-apply):**

- **FR-009** A one-shot migration entry point (per plan.md Decision D1) MUST walk every PRD at `docs/features/<date>-<slug>/PRD.md` AND `products/<slug>/features/<date>-<slug>/PRD.md`, parse the body's `### Source Issues` table, compose a candidate `derived_from:` block (plus `distilled_date:` derived from the PRD's body `**Date**:` line and `theme:` derived from the directory basename), and write a single review preview to `.kiln/logs/prd-derived-from-backfill-<timestamp>.md`. The migration NEVER calls `Edit` or `Write` against any PRD file — it emits diff hunks the maintainer reviews and applies manually. The migration MUST validate that each candidate `derived_from:` entry exists on disk at the parsed path; entries that do not exist are flagged inline in the hunk (commented out or annotated, per contracts §3). (PRD FR-009)

- **FR-010** The migration MUST be idempotent. A PRD that already has a `derived_from:` key in its frontmatter is skipped — zero hunks emitted for it. A second invocation on the same repo state MUST produce a preview containing `0 items` (or an empty bundled section that explicitly reads `no PRDs to backfill`). (PRD FR-010, NFR-003)

- **FR-011** PRDs under `products/<slug>/features/<date>-<slug>/PRD.md` follow the same shape and write into the same preview file. No special-casing of the product-directory path layout. (PRD FR-011)

### Non-Functional Requirements

- **NFR-001** Backwards compatibility. Existing PRDs (pre-migration, no `derived_from:` frontmatter) continue to work end-to-end. Step 4b and the hygiene rule both fall back to the scan-and-match behavior and emit output byte-identical to today's on the fallback path. In-flight pipelines that span the update do not break. (PRD NFR-001; verified by SC-007.)

- **NFR-002** Plugin portability. All reader/writer changes live under `plugin-kiln/skills/kiln-distill/SKILL.md`, `plugin-kiln/skills/kiln-build-prd/SKILL.md`, `plugin-kiln/skills/kiln-hygiene/SKILL.md`, and `plugin-kiln/rubrics/structural-hygiene.md`. The migration entry point lives within `plugin-kiln/` (final location depends on plan.md Decision D1). NO workflow command-step scripts are introduced; the CLAUDE.md `${WORKFLOW_PLUGIN_DIR}` invariant is trivially satisfied. Any future refactor that moves logic into a workflow command-step script MUST resolve it via `${WORKFLOW_PLUGIN_DIR}/scripts/...`. (PRD NFR-002)

- **NFR-003** Idempotence and determinism. (a) A second distill run on the same set of inputs writes byte-identical `derived_from:` output (sorted within each source-type group by filename ASC; feedback group precedes issue group). (b) A second Step 4b run on an already-archived PRD is a no-op — `matched=0 archived=0 missing_entries=[]`. (c) A second migration run produces zero new hunks. (PRD NFR-003, FR-010)

- **NFR-004** No new MCP calls. The migration, the Step 4b reader, and the hygiene rule changes are pure local-file operations (plus the existing `gh pr list` already in hygiene). No Obsidian writes, no new GitHub calls beyond what already exists. (PRD NFR-004)

- **NFR-005** Diagnostic continuity. The Step 4b 6-field PR-#146 diagnostic MUST continue to emit on every run — both frontmatter path AND scan-fallback path. The two new fields (`derived_from_source:` and `missing_entries:`) are APPENDED at the end of the line; no existing field is removed, reordered, or renamed. Existing grep-anchored patterns from `specs/pipeline-input-completeness/SMOKE.md` §5.3 MUST still match without modification. (PRD NFR-005; verified by SC-007 re-run.)

## Success Criteria

- **SC-001 — Distill writes the frontmatter block.** Run `/kiln:kiln-distill` on a fixture backlog (1 feedback + 1 issue). Inspect the generated `docs/features/<date>-<slug>/PRD.md`: the first three non-blank lines of the file are `---`, then YAML keys in the exact order `derived_from:`, `distilled_date:`, `theme:`, closing `---` before the `# Feature PRD` heading. Verified by the SMOKE.md §5.1 assertion. (PRD SC-001)

- **SC-002 — Build-prd Step 4b flips every `derived_from:` entry on the frontmatter path.** Run `/kiln:kiln-build-prd` on a fixture PRD with `derived_from: [.kiln/feedback/a.md, .kiln/issues/b.md]`. Both files archive to `completed/`, both get `status: completed` + `completed_date:` + `pr:`. The diagnostic line reports `derived_from_source: frontmatter`, `missing_entries: []`, `matched=2`. Verified by SMOKE.md §5.2. (PRD SC-002)

- **SC-003 — Step 4b falls back cleanly on a pre-migration PRD.** Point a pipeline at `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` (shipped before this feature; has no `derived_from:`). Pipeline completes successfully; diagnostic line reports `derived_from_source: scan-fallback`, `missing_entries: []`. Verified by the SC-007 verification log in Phase F. (PRD SC-003)

- **SC-004 — Hygiene emits correct signals for mixed-state repos.** Run `/kiln:kiln-hygiene` against a fixture with one migrated PRD (has `derived_from:`) and one unmigrated PRD (no `derived_from:`). The preview contains signals for both — the migrated PRD's signals come from the frontmatter path, the unmigrated PRD's signals come from the walk-backlog fallback. Output for the unmigrated PRD is byte-identical to today's output (diff against a pre-change golden fixture). Verified by SMOKE.md §5.3. (PRD SC-004)

- **SC-005 — Migration is idempotent.** Run the migration twice against the same repo. The second run's preview either reports `0 items to backfill` or writes an empty `## Bundled: derived_from-backfill (0 items)` section and no hunks. Verified by SMOKE.md §5.4. (PRD SC-005)

- **SC-006 — Frontmatter and body table agree byte-for-byte in path order.** For every PRD generated by `/kiln:kiln-distill` during SC-001's smoke run, the ordered list of paths in `derived_from:` equals the ordered list of paths in the `### Source Issues` table's first column. Verified by SMOKE.md §5.1's diff-check assertion. (PRD SC-006, FR-002)

- **SC-007 — Backwards-compat run against a pre-migration PRD completes unchanged.** Run `/kiln:kiln-build-prd` against `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` (PR-#146's PRD; no `derived_from:`) in a verification branch. Capture stdout + `.kiln/logs/build-prd-step4b-<TODAY>.md`. The PR-#146 SMOKE.md §5.3 grep regex against the captured diagnostic line STILL matches. Document in `agent-notes/implementer.md` under a "Backwards-compat verification" section. (PRD SC-007, NFR-001, NFR-005)

- **SC-008 — SMOKE.md fixture document exists.** `specs/prd-derived-from-frontmatter/SMOKE.md` contains: (a) a before/after `derived_from:` frontmatter sample, (b) a Step 4b diagnostic line with both new fields present (frontmatter path AND scan-fallback path examples), (c) a migration diff hunk sample (unified-diff format, matching the bundled-accept-or-reject shape from hygiene). Each fixture ends with copy-pasteable bash assertions that print `OK` or `FAIL`. (PRD SC-008)

## Out of Scope (defers to follow-on PRDs)

- Propagation of `derived_from:` into `docs/PRD.md` or `products/<slug>/PRD.md` (product-level PRDs have no source items; PRD Non-Goals).
- Schema changes to `.kiln/feedback/` or `.kiln/issues/` frontmatter (`prd:` key stays as-is; PRD Non-Goals).
- Removal of the 6-field Step 4b diagnostic (kept as backwards-compat guard; PRD Non-Goals).
- A policy engine that asserts "all frontmatter fields must be consumed by something" (PRD Non-Goals).
- A hygiene rule that checks `derived_from:` frontmatter against the `### Source Issues` body table for drift after hand-edits (PRD Risk 2 defers to a follow-on).
- Any change to how `/kiln:kiln-distill` groups items into themes (FR-012 ordering is a precondition, not a deliverable).
- A CLI flag / agent entry point to force-refresh `derived_from:` on already-migrated PRDs (idempotence is preserve-or-skip, not re-derive).

## Dependencies & Assumptions

- **PR #146 (`pipeline-input-completeness`) is merged.** Step 4b's existing 6-field diagnostic and its scan-and-match fallback are the contract surface this spec extends. If PR #146 is reverted, Phase B of this spec's task list regresses first; the implementer MUST NOT ship Phase B without PR #146's changes present.
- **`$PRD_PATH` is already in scope at Step 4b time.** Set in Pre-Flight step 3 of `/kiln:kiln-build-prd`. No new contract surface.
- **`$PR_NUMBER` reported by audit-pr to the team lead.** Unchanged from PR #146.
- **`gh` CLI available for the hygiene rule's primary path.** The frontmatter-walking primary path still needs the bulk `gh pr list` call to map slug → PR number. No change to FR-006's graceful-degradation path (marks every candidate `inconclusive` if `gh` is unavailable).
- **`date -u +%Y-%m-%d`** is the canonical shape for `distilled_date:` (plan.md Decision D2).
- **Hand-authored PRDs** (product-level `docs/PRD.md`, `products/<slug>/PRD.md`, or feature PRDs written by hand without going through distill) follow plan.md Decision D3 — MAY carry `derived_from: []` or omit the frontmatter entirely. Both cases fall through Step 4b's scan-fallback path (FR-005) with no special-case logic.

## Risks (carried from PRD)

| Risk | Mitigation in this spec |
|---|---|
| Migration false positives on hand-edited `### Source Issues` tables | FR-009 writes a propose-don't-apply preview; human review is the gate. FR-009 additionally validates every candidate `derived_from:` entry exists on disk and flags mismatches in the hunk. |
| Drift between `derived_from:` frontmatter and `### Source Issues` body table after distill | FR-002 invariant check in distill (abort on drift at write time); SC-006 asserts equality byte-for-byte in the smoke fixture. Post-hoc hand-edit drift is OUT OF SCOPE (deferred to follow-on). |
| Path format drift (absolute / Windows-like / mixed case) | FR-003 fixes format at write time. Readers trust the written format; no normalization is performed on read (any drift is a distill bug, not a reader bug). |
| Existing grep-anchored tests break when new diagnostic fields are added | FR-006 / NFR-005 pin the new fields to the END of the diagnostic line; FR-006 states explicitly the original 6 fields stay in their current positions. SC-007's verification log re-runs PR-#146's SMOKE.md §5.3 grep regex against the captured line. |
| Hand-authored PRD policy ambiguity | plan.md Decision D3 — MAY carry `derived_from: []` OR omit frontmatter; both handled by scan-fallback path. |
| Plugin portability regression | NO workflow command-step scripts are introduced. NFR-002 documents the `${WORKFLOW_PLUGIN_DIR}` invariant for any future refactor. |

## Acceptance Definition

This spec is "implemented" when:

- All 11 FRs are met (verified by SC-001 through SC-008).
- `tasks.md` is fully `[X]`.
- `specs/prd-derived-from-frontmatter/SMOKE.md` exists with the three fixture sections (frontmatter before/after, extended diagnostic line, migration diff hunk).
- `specs/prd-derived-from-frontmatter/agent-notes/implementer.md` contains the Phase F backwards-compat verification log (SC-007).
- A clean run of `/kiln:kiln-build-prd` on this PRD itself archives this spec's source feedback file (`.kiln/feedback/2026-04-24-prds-generated-by-kiln-kiln-distill-should-carry.md`) into `.kiln/feedback/completed/` via the frontmatter path (not the fallback), with the diagnostic reporting `derived_from_source: frontmatter` and `missing_entries: []`.
- `/kiln:kiln-hygiene` after the merge reports zero `merged-prd-not-archived` items for this PRD's slug via the frontmatter primary path.
