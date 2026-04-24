# Implementation Plan: PRD `derived_from:` Frontmatter

**Spec**: [spec.md](./spec.md)
**Branch**: `build/prd-derived-from-frontmatter-20260424`
**Date**: 2026-04-24

## Overview

Four surgical plugin-source edits + one propose-don't-apply migration:

1. **Distill writer** — add a YAML frontmatter-emit step to `plugin-kiln/skills/kiln-distill/SKILL.md` Step 4 (between source-selection and body rendering). Same in-memory list feeds both the frontmatter block and the `### Source Issues` body table (FR-002 invariant).
2. **Build-prd Step 4b reader + fallback** — add a `read_derived_from()` helper near the top of Step 4b, branch on frontmatter-present vs frontmatter-absent, and extend the diagnostic line with two APPENDED fields. ~40 lines of bash added to the existing ~130-line Step 4b body.
3. **Hygiene rule primary-path switch** — add a per-PRD iteration that reads `derived_from:` before the existing walk-backlog loop; the walk-backlog loop becomes the fallback (only processes items whose `prd:` points at a PRD lacking `derived_from:`). Update `plugin-kiln/rubrics/structural-hygiene.md` to describe the new primary path.
4. **Migration entry point** — per Decision D1 below, shipped as a subcommand of `/kiln:kiln-hygiene` (`/kiln:kiln-hygiene backfill` or equivalent). Propose-don't-apply; writes `.kiln/logs/prd-derived-from-backfill-<timestamp>.md`.

No new dependencies. No workflow command-step scripts. No new skill files.

## Locked Decisions

### Decision D1 — Migration entry point: HYGIENE SUBCOMMAND (resolves PRD Open Question 1)

**Read**: PRD §Risks & Open Questions Q1; existing propose-don't-apply precedents in `/kiln:kiln-claude-audit` and `/kiln:kiln-hygiene`; team-lead recommendation in pipeline kickoff message.

**Decision**: Ship the backfill as a **subcommand of `/kiln:kiln-hygiene`** — invoked as `/kiln:kiln-hygiene backfill` (or the idiomatic args-dispatch form used by hygiene today). NOT a separate `/kiln:kiln-prd-backfill` top-level skill.

**Rationale**:

- **Single propose-don't-apply entry point.** `/kiln:kiln-hygiene` already owns `.kiln/logs/structural-hygiene-<timestamp>.md` review previews. The backfill preview (`.kiln/logs/prd-derived-from-backfill-<timestamp>.md`) uses the same review-preview shape (Signal Summary + bundled-accept sections). Consolidating under hygiene means maintainers have ONE entry point for "audit-style, propose-don't-apply" operations, which aligns with CLAUDE.md's discoverability expectations.
- **Shared rubric-loading / preview-rendering code path.** Hygiene already renders bundled-accept-or-reject sections (`## Bundled: merged-prd-not-archived (<N> items)`). The backfill section (`## Bundled: derived_from-backfill (<N> items)`) is the same shape with a different rule_id. Factoring the bundle-writer helper once in hygiene is cheaper than duplicating it.
- **Lifecycle.** The migration is a one-shot in the sense that each PRD needs it only once, but the subcommand stays callable forever — new PRDs written pre-migration still get their backfill proposal. As a `/kiln:kiln-hygiene` subcommand it survives naturally; as a standalone `/kiln:kiln-prd-backfill` it would become a vestigial entry point with no recurring reason to exist.
- **Team-lead recommendation confirmed.** Kickoff message explicitly recommended this option with rationale — pipeline lead has the product context to make this call.

**Implication for tasks.md**: Phase D edits `plugin-kiln/skills/kiln-hygiene/SKILL.md` to add a `backfill` subcommand dispatcher (or args branch). NO new top-level skill file is created under `plugin-kiln/skills/`. The subcommand entry point is documented in the hygiene skill body AND in the CLAUDE.md command list block (Phase D also updates the CLAUDE.md "Available Commands" section).

**PRD-text note**: the PRD's User Story 3 (US-006 in this spec) references `/kiln:kiln-prd-backfill` as "(or equivalent)". Decision D1 resolves to "equivalent" — implementer uses the hygiene subcommand form. All SMOKE.md fixtures and smoke assertions reference the hygiene subcommand syntax verbatim.

### Decision D2 — `distilled_date:` format: UTC ISO-8601 DATE (resolves PRD Open Question 2)

**Read**: PRD §Risks Q2; existing `/kiln:kiln-feedback` and `/kiln:kiln-report-issue` `date:` conventions (`YYYY-MM-DD`); constitutional reference to `date -u +%Y-%m-%d` in Step 4b (pipeline-input-completeness spec).

**Decision**: `distilled_date:` is a UTC ISO-8601 date in `YYYY-MM-DD` format (date only, no time, no timezone suffix). Produced by `date -u +%Y-%m-%d` at distill time.

**Rationale**:

- **Matches existing kiln conventions.** `/kiln:kiln-feedback` writes `date: 2026-04-24` (date only); `/kiln:kiln-report-issue` does the same; hygiene's `merged_date` field uses `${merged_at%%T*}` to strip the time component from `mergedAt`. The new field slots into a well-established convention — no one has to relearn the format.
- **Determinism.** NFR-003 requires a second distill run on unchanged inputs to produce byte-identical frontmatter. A date field (no time) makes that invariant hold for 24 hours of the same UTC day — the only scenario where it matters is re-running distill within minutes, and the day-grained value is stable across that.
- **Consumer shape.** No consumer in this PRD's scope reads `distilled_date:` (PRD Non-Goals). If a future consumer needs sub-day precision it can be raised as a separate schema evolution — widening the field is cheap; narrowing is not.

**Implication for tasks.md**: Phase A's distill edit uses `date -u +%Y-%m-%d`. No helper script needed — the inline `$(date -u +%Y-%m-%d)` is sufficient. The migration (Phase D) derives `distilled_date:` from the PRD body's `**Date**: YYYY-MM-DD` line; if the body line is absent or malformed, the migration falls back to the PRD file's mtime formatted as `date -u -r <file> +%Y-%m-%d` and annotates the hunk with a comment (`# distilled_date inferred from file mtime — review`).

### Decision D3 — Hand-authored PRD policy (resolves PRD Open Question 3)

**Read**: PRD §Risks Q3; PRD §Non-Goals (product-level PRDs out of scope); spec FR-005 (scan-fallback on missing frontmatter).

**Decision**: Hand-authored PRDs (PRDs written without going through `/kiln:kiln-distill`) MAY carry `derived_from: []` (empty list) OR omit the frontmatter block entirely. Both cases fall through Step 4b's scan-fallback path (FR-005). Neither case triggers an error. NO special-case logic is added to Step 4b, hygiene, or the migration to distinguish "empty list" from "absent block" — both paths converge on the fallback.

**Rationale**:

- **No policy overhead.** The simplest thing that works: an empty `derived_from:` is treated as "there are zero source items to archive" — which is literally true for a hand-authored PRD with no backlog origin. Step 4b's frontmatter-path logic on an empty list archives zero items and reports `matched=0 archived=0 missing_entries=[]` — a clean no-op. The scan-fallback ALSO reports zero matches against a hand-authored PRD (no backlog item has that PRD's path in its `prd:` field). So the two paths converge on the same correct output.
- **Explicit FR-006 carve-out.** The `matched == len(derived_from)` invariant (FR-006) naturally accepts `len(derived_from) == 0` → `matched == 0`. No additional guard needed.
- **Migration handling.** The migration (Phase D) only emits hunks for PRDs that (a) lack `derived_from:` entirely AND (b) contain a parseable `### Source Issues` table with at least one row pointing at an existing backlog file. Hand-authored PRDs typically have neither a `### Source Issues` table nor a backlog origin — the migration emits zero hunks for them naturally. If a hand-authored PRD happens to contain a hand-written Source Issues table, the migration's diff hunk is up for human review like any other (propose-don't-apply discipline).

**Implication for tasks.md**: NO extra tasks. The `empty list is a valid frontmatter-path input` behavior falls out of the reader loop in Phase B. The migration's "skip PRDs already carrying `derived_from:`" predicate (Phase D) treats `derived_from: []` as "already migrated" — idempotence (FR-010) holds.

## Architecture & Tech Stack

Inherited — no additions:

- **Language**: Bash 5.x (all readers + migration + distill helpers), Markdown (SKILL.md + rubric + SMOKE.md).
- **Tools**: `grep`, `sed`, `awk`, `tr`, `date`, `find`, `git`. All POSIX. `jq` already present for hygiene's signal rendering — reused for `missing_entries:` JSON array emission in the Step 4b diagnostic.
- **MCP**: NONE new. `gh` CLI continues to be used only by the hygiene rule (unchanged since PR #146).
- **No new agents.** Distill, build-prd, and hygiene all run in the team lead's main-chat context (hygiene's sub-workflow structure is already in place; Phase C edits the skill body).
- **No new workflow command-step scripts.** NFR-002 invariant is trivially satisfied.

## File Touch List

### Modified

| File | Change | Phase |
|---|---|---|
| `plugin-kiln/skills/kiln-distill/SKILL.md` | Step 4 body: emit YAML frontmatter block before the `# Feature PRD` heading; render `### Source Issues` from the same in-memory list; invariant check for drift | A |
| `plugin-kiln/skills/kiln-build-prd/SKILL.md` | Step 4b body: add `read_derived_from()` helper, branch on frontmatter-present vs -absent, extend diagnostic line with `derived_from_source:` and `missing_entries:` appended fields | B |
| `plugin-kiln/skills/kiln-hygiene/SKILL.md` | Step 5c body: add per-PRD frontmatter-walk primary path; walk-backlog loop becomes the fallback; add `backfill` subcommand dispatcher | C, D |
| `plugin-kiln/rubrics/structural-hygiene.md` | `merged-prd-not-archived` rule text: describe the new primary path; keep the fallback description; add rubric entry for the `derived_from-backfill` rule emitted by the new subcommand | C, D |
| `CLAUDE.md` | Add a one-line entry for the `/kiln:kiln-hygiene backfill` subcommand under "Available Commands" | D |

### Created

| File | Purpose | Phase |
|---|---|---|
| `specs/prd-derived-from-frontmatter/spec.md` | This spec | (specifier) |
| `specs/prd-derived-from-frontmatter/plan.md` | This plan | (specifier) |
| `specs/prd-derived-from-frontmatter/tasks.md` | Task breakdown | (specifier) |
| `specs/prd-derived-from-frontmatter/contracts/interfaces.md` | Frontmatter block shape, extended diagnostic schema, migration diff preview layout, parse routines | (specifier) |
| `specs/prd-derived-from-frontmatter/SMOKE.md` | Fixture + assertion document (SC-008) | E |
| `specs/prd-derived-from-frontmatter/agent-notes/<agent>.md` | Friction notes | (per agent) |

### Deleted

None.

## Phase Plan

### Phase A — Distill writer: emit `derived_from:` frontmatter + FR-002 invariant check (FR-001, FR-002, FR-003)

Edit `plugin-kiln/skills/kiln-distill/SKILL.md` Step 4. Before the body-heading block, insert a YAML frontmatter emit step that:

1. Composes the in-memory `derived_from` list from the already-selected feedback + issue items (feedback first, then issues; within each group sorted by filename ASC).
2. Writes the frontmatter block in the exact key order `derived_from:` / `distilled_date:` / `theme:` (contracts §1).
3. Renders the `### Source Issues` body table from the SAME in-memory list (not from a separate traversal) — FR-002 invariant.
4. Asserts (at write time) that `derived_from_paths == [row.path for row in source_issues_table]` — abort with a clear error if they differ (the invariant check prevents drift from being introduced by a future refactor).

**Files**: `plugin-kiln/skills/kiln-distill/SKILL.md`.
**Tasks**: 2 (T01-1 frontmatter block + key order; T01-2 same-list invariant + body table render).

### Phase B — Build-prd Step 4b: frontmatter-path reader + extended diagnostic (FR-004, FR-005, FR-006)

Edit `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b. Add:

1. A `read_derived_from()` helper (contracts §2) that extracts the `derived_from:` list from the PRD's YAML frontmatter using a bounded awk extractor (read first `---`…`---` block only; reject PRDs where the block is missing or malformed).
2. A branch at the top of Step 4b: if `derived_from:` is present AND non-empty → frontmatter path (iterate list, archive each entry, track `missing_entries`). Else → fall through to the existing PR-#146 scan-fallback loop unchanged.
3. An extended diagnostic line that APPENDS two new fields AFTER the existing 6 fields:

```
step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<A> skipped=<S> prd_path=<P> derived_from_source=<frontmatter|scan-fallback> missing_entries=<JSON-array>
```

**Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.
**Tasks**: 3 (T02-1 `read_derived_from()` helper; T02-2 frontmatter-path archive loop + missing-entries tracking; T02-3 extended diagnostic line + grep-anchor preservation).

### Phase C — Hygiene rule: frontmatter-walk primary + walk-backlog fallback (FR-007, FR-008)

Edit `plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 5c and `plugin-kiln/rubrics/structural-hygiene.md`. Add:

1. A per-PRD walk that reads `derived_from:` and emits one signal per entry (archive-candidate / needs-review / inconclusive, keyed by slug against the existing `MERGED_BY_SLUG` map).
2. Track the set of PRDs already processed via frontmatter; the existing walk-backlog loop ONLY processes items whose `prd:` points at a PRD NOT in that set (pre-migration fallback).
3. Rubric text update: describe the two-path behavior in the `merged-prd-not-archived` rule YAML block.

**Files**: `plugin-kiln/skills/kiln-hygiene/SKILL.md`, `plugin-kiln/rubrics/structural-hygiene.md`.
**Tasks**: 2 (T03-1 frontmatter-walk primary + processed-PRD set; T03-2 rubric text update + fallback scope narrowing).

### Phase D — Migration subcommand: `/kiln:kiln-hygiene backfill` (FR-009, FR-010, FR-011)

Edit `plugin-kiln/skills/kiln-hygiene/SKILL.md` to add a `backfill` subcommand dispatcher. Edit `plugin-kiln/rubrics/structural-hygiene.md` to add the `derived_from-backfill` rule entry. Edit `CLAUDE.md` to document the subcommand. The subcommand logic:

1. Walks `docs/features/*/PRD.md` AND `products/*/features/*/PRD.md`.
2. For each PRD: skip if the YAML frontmatter already contains `derived_from:` (idempotence — FR-010).
3. For eligible PRDs: parse `### Source Issues` table, validate each path exists on disk (annotate non-existent rows), compose candidate YAML frontmatter block, emit one unified-diff hunk.
4. Write `.kiln/logs/prd-derived-from-backfill-<timestamp>.md` with a single `## Bundled: derived_from-backfill (<N> items)` section grouping all hunks sorted by PRD path ASC.
5. Propose-don't-apply — NEVER calls `Edit`/`Write` against any PRD file.

**Files**: `plugin-kiln/skills/kiln-hygiene/SKILL.md`, `plugin-kiln/rubrics/structural-hygiene.md`, `CLAUDE.md`.
**Tasks**: 3 (T04-1 subcommand dispatcher + args parse; T04-2 per-PRD diff hunk composer with path validation; T04-3 bundled section writer + CLAUDE.md entry).

### Phase E — Smoke fixtures + SMOKE.md (SC-008)

Create `specs/prd-derived-from-frontmatter/SMOKE.md` with three fixture sections (contracts §5):

1. **§5.1 Distill writer fixture (SC-001, SC-006)** — scaffolds 1 feedback + 1 issue, runs distill (or a bash simulation of the write step), asserts the frontmatter block is at the top of the output PRD with keys in FR-001 order, asserts `derived_from:` list equals the Source Issues table's path column byte-for-byte.
2. **§5.2 Step 4b extended diagnostic fixture (SC-002, SC-003)** — two sub-fixtures: (a) PRD with `derived_from:` → captured diagnostic line has `derived_from_source=frontmatter missing_entries=[]`; (b) pre-migration PRD (no frontmatter) → `derived_from_source=scan-fallback missing_entries=[]`. Both cases pass the PR-#146 SMOKE.md §5.3 grep regex.
3. **§5.3 Hygiene + migration fixture (SC-004, SC-005)** — mixed-state fixture with one migrated PRD + one unmigrated PRD; runs hygiene, inspects the preview for the expected signal rows. Runs migration subcommand twice; asserts second run emits `0 items`.

Each block ends with copy-pasteable bash printing `OK` or `FAIL`.

**Files**: `specs/prd-derived-from-frontmatter/SMOKE.md`.
**Tasks**: 2 (T05-1 distill + Step 4b fixtures; T05-2 hygiene + migration fixtures).

### Phase F — Backwards-compat verification (NFR-001, NFR-005, SC-007)

Run `/kiln:kiln-build-prd` against a pre-migration PRD in a verification sandbox. Capture:

1. The diagnostic line that Step 4b wrote to stdout and to `.kiln/logs/build-prd-step4b-<TODAY>.md`.
2. Apply `specs/pipeline-input-completeness/SMOKE.md` §5.3's grep regex against the captured line — confirm it still matches (NFR-005 anchors preserved).
3. Inspect archival — `.kiln/issues/completed/` and `.kiln/feedback/completed/` have the expected post-run state as if PR #146 alone had run.

Document the verification in `specs/prd-derived-from-frontmatter/agent-notes/implementer.md` under a "Backwards-compat verification" section.

**Files**: `specs/prd-derived-from-frontmatter/agent-notes/implementer.md` (verification log only — no plugin-source changes in this phase).
**Tasks**: 1 (T06-1 SC-007 verification + NFR-005 grep-anchor replay).

## Risks (implementation-side)

| Risk | Mitigation |
|---|---|
| Distill's existing body template is one long markdown literal — easy to mis-indent the new frontmatter block | Pin the block shape in `contracts/interfaces.md` §1 verbatim; the implementer copies the literal skeleton (4 lines `---` / `derived_from:` / `distilled_date:` / `theme:` / `---`) and only parameterizes the list and date values |
| Step 4b's diagnostic grep regex in PR-#146's SMOKE.md §5.3 will silently break if the new fields are inserted in the middle of the line | NFR-005 / FR-006 mandate APPENDING the new fields AFTER `prd_path=<PRD_PATH>`; contracts §2 pins the field order; SC-007's verification log replays the PR-#146 regex against the new line as an explicit check |
| `read_derived_from()` helper might over-match on a `---` delimiter that appears inside a list value | Helper reads the FIRST `---`/`---` pair only (awk state machine with a `seen_start` flag; closes on the first `---` line after `seen_start`). Contract §2 pins the awk body verbatim. |
| Hygiene's dual-path logic double-counts items (both frontmatter path AND walk-backlog fallback emit a signal for the same item) | Phase C T03-1 tracks a `PROCESSED_PRDS` set; the walk-backlog loop skips any item whose `prd:` is in that set. Contracts §3 pins the dedup rule. |
| Migration false-positive: `### Source Issues` table in a hand-authored PRD contains a path that doesn't look like a backlog file (e.g., external URL) | Per-row path validation: if the parsed path does not exist on disk, the row is included in the hunk with a leading `# ` comment annotation (`# path does not exist on disk — review`). Maintainer decides whether to keep, drop, or fix during review. |
| Consumers forget that `derived_from: []` is a valid frontmatter-path input | Decision D3 + contracts §2 explicitly document the empty-list case; Step 4b's frontmatter-path branch checks `len(derived_from) > 0` — on empty list it falls through to scan-fallback naturally (both paths produce the same output for hand-authored PRDs, so the fall-through is correct). |
| Rubric-file edit breaks hygiene's existing output on an unrelated rule | Phase C T03-2 edits ONLY the `merged-prd-not-archived` rule block and adds a new `derived_from-backfill` rule block; no other rule text changes. |
| Future refactor moves logic into a workflow command-step script and uses a repo-relative path | NFR-002 + plan.md §Architecture explicitly document the `${WORKFLOW_PLUGIN_DIR}` invariant for any such refactor. Not in scope for this spec (no scripts are introduced here). |

## Verification Gates

Before marking any task completed, the implementer MUST:

1. Run the SMOKE.md §5.1 fixture; assertion prints `OK`.
2. Run the SMOKE.md §5.2 fixture (both sub-fixtures); assertions print `OK` and the PR-#146 grep regex matches the new diagnostic line.
3. Run the SMOKE.md §5.3 fixture; both hygiene and migration assertions print `OK`.
4. Re-run the migration on the same state immediately after the first run; preview's bundled section reports `0 items`.
5. Run the SC-007 verification (Phase F) against `docs/features/2026-04-23-pipeline-input-completeness/PRD.md`; document result in `agent-notes/implementer.md`.
6. `jq . <preview-JSON-output-if-any>` exits 0 (no JSON output in scope today; placeholder for future schema-rendered previews).

The auditor MUST verify all 8 SCs against the final state and confirm the Phase F verification log is present and conclusive. No partial credit.
