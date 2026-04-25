# Feature Specification: Workflow Governance

**Feature Branch**: `build/workflow-governance-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-24-workflow-governance/PRD.md` (frozen)
**Derived From**:
- `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md` (hook fix — already shipped; see "Existing Work")
- `.kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md`
- `.kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md`

## Overview

Close three governance gaps in the kiln pipeline so it can (a) write its own artifacts on its own `build/*` branches, (b) refuse un-roadmapped input at the PRD-distill step, and (c) feed retro-proposed prompt-improvements (PIs) back to the source tree as a reviewable diff. The three sub-initiatives are independently releasable (PRD NFR-004). This spec covers all three in one pipeline run so the governance claim lands coherently.

## Existing Work

**FR-001 and FR-002 of the PRD have already shipped.** Commit `86e3585` extended `plugin-kiln/hooks/require-feature-branch.sh` line 50 to accept `build/*` in the branch accept-list:

```bash
if [[ "$BRANCH" =~ ^[0-9]{3}- ]] || [[ "$BRANCH" =~ ^[0-9]{8}-[0-9]{6}- ]] || [[ "$BRANCH" == build/* ]]; then
```

The stale source issue `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md` is listed in the PRD's `derived_from:` because it motivated the change; it is kept for provenance but the underlying code change is NOT re-implemented by this spec. This spec treats FR-001/FR-002 as **verification-only** — confirmed with a thin test fixture (FR-003 of the PRD) that exercises the already-shipped hook against a simulated `build/workflow-governance-20260424` branch. All other PRD FRs (FR-003 through FR-013) remain full implementation work.

## Clarifications

The PRD is frozen; the following implementation-shaping decisions were resolved during spec drafting. Each one closes an open question carried forward from the PRD's "Risks & Open Questions" section or from the team-lead's brief.

1. **FR-001/FR-002 verification vs re-implementation** — The hook change already shipped. This spec adds the FR-003 test fixture only. No hook source edit. No version bump on the hook. (Resolves team-lead clarification: "treat these as verification-only.")
2. **FR-008 grandfathering scope** — Pre-existing PRDs whose `derived_from:` cites raw `.kiln/issues/` or `.kiln/feedback/` paths MUST continue to validate under the new distill gate. Enforcement is forward-looking from the PRD's own `distilled_date:` field; the gate checks only the *next* distill invocation, not historical artifacts. No walk-and-migrate step is run. (Resolves PRD NFR-005 + team-lead clarification.)
3. **FR-006 byte preservation on `--promote`** — When `/kiln:kiln-roadmap --promote <source>` updates the source issue/feedback file, it MUST preserve the body byte-for-byte; only frontmatter `status:` and `roadmap_item:` fields may change. No reflow, no trailing-whitespace normalization, no blank-line rewriting. (Resolves PRD NFR-003 + team-lead clarification.)
4. **FR-005 per-entry confirm-never-silent UI** — The distill promotion hand-off MUST offer per-entry accept/skip (not a single global confirm). User-declined entries are excluded from the distill run; accepted entries route one-at-a-time through `/kiln:kiln-roadmap --promote` and are re-read into the distill bundle after promotion completes. (Resolves PRD FR-005 ambiguity on UX granularity.)
5. **R-2: interview short-circuit on `--promote`** — If the source issue/feedback file already contains enough structured detail (title + body ≥ 200 chars), the adversarial interview runs with per-question coached suggestions pre-filled from the source, and the user may type `accept-all` at any point (same coached pattern as `/kiln:kiln-roadmap` item capture). If the source is sparse (<200 chars of body), the full interview runs without pre-fill. (Resolves PRD R-2.)
6. **R-4: stale PI anchor policy** — When a PI block's target anchor no longer exists in the source tree, `/kiln:kiln-pi-apply` MUST mark the PI as `status: stale` in the report and skip the diff emission for that PI. No auto-rewrite of anchors. Maintainer re-anchors manually or closes the retro issue. (Resolves PRD R-4.)
7. **FR-011 pi-hash algorithm** — `pi-hash = sha256(source_issue_number || "|" || target_file_path || "|" || target_anchor || "|" || proposed_diff_text)`, truncated to first 12 hex chars. Stable across re-runs when inputs are unchanged; changes when any input changes. (Resolves PRD FR-011 under-specification.)
8. **FR-013 `/kiln:kiln-next` integration threshold** — Default threshold is 3 open retro issues with at least one unresolved PI each. Implemented as a read-only count inside `/kiln:kiln-next`'s triage pass; surfaces as a queued maintenance recommendation, not as a blocker. (Resolves PRD FR-013 default-threshold ambiguity.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Build-prd branch writes to specs/ without hook blocks (Priority: P1)

A pipeline teammate spawned by `/kiln:kiln-build-prd` is on branch `build/<slug>-<YYYYMMDD>` and edits a file under `specs/<slug>/`. The `require-feature-branch.sh` hook accepts the branch name and returns exit 0.

**Why this priority**: Every pipeline teammate hits this hook. Until it verifies clean, no downstream governance change can land under pipeline-authored branches.

**Independent Test**: Run the FR-003 test fixture (`plugin-kiln/tests/require-feature-branch-build-prefix/`) against a simulated `build/workflow-governance-20260424` branch with a `specs/workflow-governance/spec.md` write payload. Assert exit code 0 and no stderr output.

**Acceptance Scenarios**:

1. **Given** the current branch is `build/workflow-governance-20260424`, **When** a write against `specs/workflow-governance/spec.md` is attempted, **Then** the hook exits 0 with no stderr.
2. **Given** the current branch is `main`, **When** a write against `specs/anything/spec.md` is attempted, **Then** the hook exits 2 with the standard "branch naming" error (regression guard — `build/*` expansion did not widen the non-pipeline path).
3. **Given** the current branch is `feature/rename-thing` (unprefixed), **When** a write against `specs/rename-thing/spec.md` is attempted, **Then** the hook exits 2 (regression guard — only `build/*`, not any `*/*`).

---

### User Story 2 — Distill refuses un-promoted sources and offers promotion (Priority: P1)

A user runs `/kiln:kiln-distill <theme>` on a theme whose open items are all raw `.kiln/issues/` or `.kiln/feedback/` entries — none have been promoted to `.kiln/roadmap/items/*.md` with `kind:` + sizing + `promoted_from:` frontmatter. The skill does NOT emit a PRD. Instead it surfaces every un-promoted entry and offers to run `/kiln:kiln-roadmap --promote` for each one.

**Why this priority**: This is the load-bearing governance claim of the PRD — the roadmap is the canonical intake, and issues/feedback are promotion sources, not direct PRD inputs.

**Independent Test**: In a fixture repo with 3 open issues under `.kiln/issues/`, 0 roadmap items, and 0 PRDs citing them, run `/kiln:kiln-distill <theme>`. Verify (1) no PRD is emitted, (2) each issue is surfaced with a per-entry accept/skip prompt, (3) on "skip all" the skill exits cleanly with exit code 0 and no side effects.

**Acceptance Scenarios**:

1. **Given** the selected theme resolves to 3 un-promoted issues and 0 roadmap items, **When** the user runs `/kiln:kiln-distill <theme>`, **Then** the skill refuses to emit a PRD and surfaces the 3 issues in a per-entry promotion prompt.
2. **Given** the promotion prompt is shown, **When** the user accepts entry 1 and skips entries 2 and 3, **Then** only entry 1 is routed through `/kiln:kiln-roadmap --promote`; after promotion, the distill bundle re-reads and contains the newly created roadmap item; entries 2 and 3 are excluded from the run.
3. **Given** the promotion prompt is shown, **When** the user declines all entries, **Then** the skill exits cleanly with no PRD emitted and no side-effect writes.
4. **Given** the selected theme resolves to 1 roadmap item (previously promoted) and 2 un-promoted issues, **When** the user runs `/kiln:kiln-distill <theme>`, **Then** the skill offers promotion for the 2 un-promoted issues and, whether the user accepts or skips, the item's presence ensures the PRD can still emit once the user chooses to proceed.
5. **Given** a pre-existing PRD at `docs/features/<date>-<slug>/PRD.md` whose `derived_from:` cites raw issue paths, **When** the distill gate rolls out, **Then** the pre-existing PRD's `derived_from:` continues to parse and validate under any subsequent frontmatter lint — no retroactive migration (FR-008 grandfathering).

---

### User Story 3 — Promote a raw issue into a roadmap item with back-reference (Priority: P1)

A user (or `/kiln:kiln-distill`'s hand-off) runs `/kiln:kiln-roadmap --promote .kiln/issues/2026-04-24-foo.md`. The skill reads the source, runs the adversarial interview (with coached pre-fill if source body ≥ 200 chars), captures kind + sizing + phase, writes a new `.kiln/roadmap/items/<date>-<slug>.md` with `promoted_from: <source-path>` in its frontmatter, and updates the source file's frontmatter to `status: promoted` + `roadmap_item: <new-item-path>`. The source body is byte-preserved.

**Why this priority**: `--promote` is the viable escape hatch that makes the distill gate non-punitive. Without it, users are stuck.

**Independent Test**: In a fixture with `.kiln/issues/2026-04-24-widget-dark-mode.md` (body 300 chars, frontmatter `status: open`), run `/kiln:kiln-roadmap --promote .kiln/issues/2026-04-24-widget-dark-mode.md`, accept all coached suggestions. Verify (1) `.kiln/roadmap/items/2026-04-24-widget-dark-mode.md` exists with valid frontmatter (kind, blast_radius, review_cost, context_cost, phase, promoted_from), (2) the source file's frontmatter is `status: promoted` and `roadmap_item: .kiln/roadmap/items/2026-04-24-widget-dark-mode.md`, (3) the source file's body (everything after the `---` closing frontmatter marker) is byte-identical to the pre-promotion state.

**Acceptance Scenarios**:

1. **Given** a source issue file with body ≥ 200 chars and `status: open`, **When** the user runs `/kiln:kiln-roadmap --promote <source>`, **Then** the interview proposes coached suggestions drawn from the source text; on `accept-all` a new item file is written with all required frontmatter fields.
2. **Given** a source feedback file with body < 200 chars, **When** the user runs `/kiln:kiln-roadmap --promote <source>`, **Then** the interview runs without pre-fill (Clarification 5).
3. **Given** a promotion succeeds, **When** the source file is re-read, **Then** its frontmatter contains `status: promoted` and `roadmap_item: <item-path>`; the body bytes are identical to pre-promotion (NFR-003 / Clarification 3).
4. **Given** a promotion succeeds, **When** the new item file is re-read, **Then** its frontmatter contains `promoted_from: <source-path>` as an exact literal match of the supplied source argument.
5. **Given** the source file is already `status: promoted`, **When** the user runs `/kiln:kiln-roadmap --promote <source>` a second time, **Then** the skill refuses with a clear "already promoted — see <roadmap_item>" message and exits without writing.
6. **Given** the supplied source path does not exist, **When** the user runs `/kiln:kiln-roadmap --promote <bad-path>`, **Then** the skill exits 2 with a "source not found" error and no side effects.

---

### User Story 4 — /kiln:kiln-pi-apply emits a consolidated PI diff report (Priority: P1)

A maintainer runs `/kiln:kiln-pi-apply` to collect every unapplied prompt-improvement (PI) from open retro issues. The skill fetches issues labeled `retrospective` via `gh`, parses each `File / Current / Proposed / Why` block, and emits one report at `.kiln/logs/pi-apply-<timestamp>.md` containing unified-diff-shaped patches targeted at `plugin-kiln/skills/**/SKILL.md` and `plugin-kiln/agents/**.md`. Nothing is written to the source tree. Each PI carries a stable `pi-hash` so a subsequent run on the same backlog emits byte-identical output.

**Why this priority**: Without this, retrospective work produces artifacts that are never read again. Closing the loop is the whole point of the PRD's third sub-initiative.

**Independent Test**: With 3 fixture retro issues containing 5 PI blocks (2 already-applied, 1 stale-anchor, 2 actionable), run `/kiln:kiln-pi-apply`. Verify (1) report at `.kiln/logs/pi-apply-<ts>.md` exists, (2) report lists 2 actionable PIs with full diff + target + Why + pi-hash, (3) 2 already-applied PIs are listed as `status: already-applied` with no diff, (4) 1 stale PI is listed as `status: stale` with no diff, (5) no source files under `plugin-kiln/skills/` or `plugin-kiln/agents/` have been modified, (6) a second invocation within the same minute emits a byte-identical report body (modulo timestamp).

**Acceptance Scenarios**:

1. **Given** 3 open retro issues labeled `retrospective` exist on GitHub, **When** the user runs `/kiln:kiln-pi-apply`, **Then** the skill fetches all 3 via `gh issue list --label retrospective --state open --json`, parses `File / Current / Proposed / Why` blocks, and writes one report at `.kiln/logs/pi-apply-<timestamp>.md`.
2. **Given** a PI block's target file + anchor already contains the proposed text verbatim, **When** the report is generated, **Then** the PI is marked `status: already-applied`, no diff is rendered, but the PI is still listed (for audit trail).
3. **Given** a PI block's target anchor no longer exists in the source tree (structural drift), **When** the report is generated, **Then** the PI is marked `status: stale`, no diff is rendered, and the report includes the anchor that was searched (Clarification 6).
4. **Given** an actionable PI (target exists, proposed text not yet present), **When** the report is generated, **Then** the entry includes source-issue URL, PI identifier (e.g. `#149 PI-1`), target file path, target anchor, unified-diff patch, the retro author's "Why" verbatim, and the `pi-hash`.
5. **Given** two consecutive runs within the same minute on an unchanged retro backlog, **When** each report is generated, **Then** the report body (excluding the report's own header timestamp) is byte-identical, enabling reviewers to diff two reports and see only "what's new."
6. **Given** the `/kiln:kiln-next` pass runs after this PRD ships, **When** the count of open retro issues with unresolved PIs is ≥ 3 (Clarification 8), **Then** `/kiln:kiln-next` surfaces `/kiln:kiln-pi-apply` as a queued maintenance recommendation.

---

### Edge Cases

- **Empty retro backlog** — `/kiln:kiln-pi-apply` with zero open retro issues writes a report stating "No open retro issues found" and exits 0. No error.
- **Retro issue with no PI blocks** — Issue is listed in the report with count `0` parseable PI blocks. No error.
- **Malformed PI block** (missing one of File/Current/Proposed/Why) — The malformed block is listed under `parse_errors:` in the report with the issue URL and the malformed block's line range; report continues on other blocks. No partial-write of the source tree.
- **GitHub API failure** — Skill surfaces the `gh` error, writes no report, exits non-zero.
- **`/kiln:kiln-roadmap --promote` invoked on a source with no frontmatter at all** — Skill refuses with "source has no frontmatter; cannot write back-reference" and exits 2.
- **Distill invoked with zero open entries across all streams** — Existing behavior preserved (no PRD emitted, friendly message). The new gate adds no new failure mode here.

## Requirements *(mandatory)*

### Functional Requirements

Every FR below maps 1:1 to a PRD FR. The FR IDs align with the PRD's numbering for traceability.

**Hook verification (FR-001 and FR-002 already shipped in commit 86e3585 — this spec covers the test fixture only)**

- **FR-001 (verification)** *(PRD FR-001)* — The `require-feature-branch.sh` hook MUST continue to accept `build/<slug>-<YYYYMMDD>` as a valid feature branch and allow `Write` / `Edit` against `specs/<slug>/`. This is verified by FR-003's test fixture; no source-code edit is made to the hook in this spec.
- **FR-002 (verification)** *(PRD FR-002)* — The hook MUST continue to reject bare `main`, `master`, and unprefixed feature branches; the `build/*` accept-list entry does NOT widen the hook to accept `*/*` patterns. This is verified by FR-003's test fixture with negative cases.
- **FR-003** *(PRD FR-003)* — A shell test fixture at `plugin-kiln/tests/require-feature-branch-build-prefix/` MUST exercise the hook against a simulated `build/workflow-governance-20260424` branch with a write path under `specs/workflow-governance/` and assert exit code 0. The fixture MUST also exercise negative cases — bare `main` (exit 2), unprefixed `feature/foo` (exit 2) — to guard FR-002.

**Roadmap-first PRD intake (distill gate + promote path)**

- **FR-004** *(PRD FR-004)* — `/kiln:kiln-distill` MUST refuse to bundle raw issues or feedback that have not been promoted to roadmap items. The skill detects "un-promoted" as: `frontmatter.status != "promoted"` AND `file is under .kiln/issues/ or .kiln/feedback/` AND `file does not have a corresponding roadmap item whose promoted_from: matches this file's path`. When the selected theme resolves to only un-promoted sources, the skill MUST NOT emit a PRD.
- **FR-005** *(PRD FR-005)* — `/kiln:kiln-distill` MUST offer a confirm-never-silent promotion hand-off at theme-selection time with per-entry accept/skip (Clarification 4). The prompt renders: "Issues/feedback not yet promoted to roadmap items: <list>. Promote these before distilling? [per-entry accept/skip]". User-declined entries are excluded from the distill run. Accepted entries route one-at-a-time through `/kiln:kiln-roadmap --promote` and are re-read into the distill bundle after promotion.
- **FR-006** *(PRD FR-006)* — `/kiln:kiln-roadmap --promote <issue-id-or-path>` MUST exist as a first-class invocation that:
  - Reads the source issue or feedback file (resolves either a raw path or an issue ID to a path)
  - Runs the adversarial interview (FR-015 of `structured-roadmap`) with coached pre-fill drawn from the source body if body ≥ 200 chars (Clarification 5)
  - Classifies `kind:` (feature / goal / research / constraint / non-goal / milestone / critique)
  - Captures `blast_radius`, `review_cost`, `context_cost`, and `phase:`
  - Writes a new `.kiln/roadmap/items/<date>-<slug>.md` with `promoted_from: <source-path>` in its frontmatter
  - Updates the source entry's frontmatter to `status: promoted` and adds `roadmap_item: <item-path>` back-link
  - Byte-preserves the source file's body (NFR-003 / Clarification 3)
- **FR-007** *(PRD FR-007)* — Distill's three-group `derived_from:` sort (feedback → item → issue) MUST be preserved as a *shape* even when the feedback and issue groups are empty in practice. Emitted PRD frontmatter always lists the three groups in order; empty groups render as absent sub-lists rather than omitting the group header. Grandfathered PRDs whose `derived_from:` lists only `feedback` and `issue` groups (no `item` group) MUST continue to parse (FR-008).
- **FR-008** *(PRD FR-008)* — Pre-existing PRDs that cite raw issues/feedback in their `derived_from:` lists MUST continue to validate and parse; no migration is triggered on them. Enforcement is forward-looking from the PRD's `distilled_date:`. Specifically: any PRD with `distilled_date:` before the distill-gate rollout date (tracked in the PRD frontmatter for this feature) is exempt from the new gate's parser assertions.

**Retro → source feedback loop (/kiln:kiln-pi-apply)**

- **FR-009** *(PRD FR-009)* — A new `/kiln:kiln-pi-apply` skill MUST read GitHub retrospective issues (filter: `label:retrospective`, state `open`), extract every `File / Current / Proposed / Why` block, and emit a single consolidated report at `.kiln/logs/pi-apply-<timestamp>.md`.
- **FR-010** *(PRD FR-010)* — The report MUST be propose-don't-apply: it renders unified-diff-shaped patches against `plugin-kiln/skills/**/SKILL.md` and `plugin-kiln/agents/**.md` but never writes to those files. Discipline matches `/kiln:kiln-claude-audit` and `/kiln:kiln-hygiene`.
- **FR-011** *(PRD FR-011)* — Each PI block in the report MUST include:
  - Source issue URL + PI identifier (e.g. `#149 PI-1`)
  - Target file + target heading/section anchor
  - Proposed unified-diff patch
  - The retro author's "Why" verbatim
  - A stable `pi-hash` computed per Clarification 7: `sha256(issue# || "|" || target_file || "|" || target_anchor || "|" || proposed_diff)` truncated to 12 hex chars
- **FR-012** *(PRD FR-012)* — The skill MUST skip diff emission for PI blocks whose target file + anchor already contain the proposed text verbatim (status: `already-applied`). It MUST mark PIs whose anchor no longer exists as `status: stale` and skip diff emission (Clarification 6). Both categories remain listed in the report for audit.
- **FR-013** *(PRD FR-013)* — `/kiln:kiln-pi-apply` MUST be discoverable from `/kiln:kiln-next` as a queued maintenance task when the count of open retro issues with unresolved PIs is ≥ 3 (Clarification 8). The `/kiln:kiln-next` integration reads the most recent `.kiln/logs/pi-apply-*.md` (if any) to determine "unresolved"; absent a prior report, it counts every open retro issue as having unresolved PIs.

### Non-Functional Requirements

- **NFR-001** *(PRD NFR-001)* — The FR-003 test fixture MUST assert `require-feature-branch.sh` runtime on the positive case is within 50ms of baseline (pre-`build/*` expansion). Baseline captured once during fixture authoring; subsequent runs compare.
- **NFR-002** *(PRD NFR-002)* — `/kiln:kiln-pi-apply` MUST complete within 60 seconds on a repo with ≤ 20 open retro issues. Measured wall-clock from skill invocation to report write.
- **NFR-003** *(PRD NFR-003)* — `/kiln:kiln-roadmap --promote` MUST preserve the source file's byte content except for the frontmatter `status:` and `roadmap_item:` fields. Enforced by a byte-diff assertion in the Phase 3 integration test (same bytes before/after for everything after the closing `---`).
- **NFR-004** *(PRD NFR-004)* — The three sub-initiatives (hook fixture, distill gate + promote, pi-apply) MUST be independently releasable. No shared script imports, no shared data schemas beyond what already exists. Each has its own test fixtures. Merge order is flexible.
- **NFR-005** *(PRD NFR-005)* — Backward compatibility: previously-distilled PRDs with raw-issue `derived_from:` entries MUST continue to parse and validate without warning under the new gate. Verified by including one real pre-existing PRD (e.g. `docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md`) in the gate-parser test fixture and asserting it parses clean.

### Traceability — PRD FR → Spec FR

| PRD FR | Spec FR | Implementation track |
|--------|---------|----------------------|
| FR-001 | FR-001 (verification) | impl-governance — fixture only |
| FR-002 | FR-002 (verification) | impl-governance — fixture only |
| FR-003 | FR-003 | impl-governance |
| FR-004 | FR-004 | impl-governance |
| FR-005 | FR-005 | impl-governance |
| FR-006 | FR-006 | impl-governance |
| FR-007 | FR-007 | impl-governance |
| FR-008 | FR-008 | impl-governance |
| FR-009 | FR-009 | impl-pi-apply |
| FR-010 | FR-010 | impl-pi-apply |
| FR-011 | FR-011 | impl-pi-apply |
| FR-012 | FR-012 | impl-pi-apply |
| FR-013 | FR-013 | impl-pi-apply |

## Success Criteria

- **SC-001** *(PRD SC-001)* — After rollout, a fresh `/kiln:kiln-build-prd` run on a non-trivial feature completes end-to-end with **zero** `require-feature-branch` hook blocks logged in `.kiln/logs/`. Verified by running the FR-003 fixture in CI and by re-executing this very pipeline (which uses `build/workflow-governance-20260424`).
- **SC-002** *(PRD SC-002)* — `/kiln:kiln-distill` refuses a run whose bundle contains only un-promoted issues and surfaces the promotion prompt. Measured: a dry-run invocation on a fixture with 3 open issues and 0 items produces the "promote these first?" per-entry dialog and exits cleanly when the user declines.
- **SC-003** *(PRD SC-003)* — `/kiln:kiln-roadmap --promote <issue-path>` produces a valid `.kiln/roadmap/items/<date>-<slug>.md` with `kind:`, all three sizing fields, `phase:`, and `promoted_from:`; the source issue's frontmatter is updated to `status: promoted` + `roadmap_item:`; the source body is byte-identical.
- **SC-004** *(PRD SC-004)* — Running `/kiln:kiln-pi-apply` on a fixture of 3 retro issues (simulating #147, #149, #152) produces a `.kiln/logs/pi-apply-<timestamp>.md` listing at minimum PI-1 (R-1 auditor blessing), PI-2 (FR-005 collision), and the version-bump drift item with correct target files and diffs. Deduplication verified: a second run within the same minute emits byte-identical output (modulo report header timestamp).
- **SC-005** *(PRD SC-005)* — The PI-1 proposal (R-1 "strict behavioral superset" blessing) is surfaced in the first `/kiln:kiln-pi-apply` report with target file `plugin-kiln/agents/prd-auditor.md` and a unified-diff patch containing the R-1 language.
- **SC-006** *(new)* — The pre-existing PRD `docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md` (which cites raw issues in its `derived_from:`) MUST continue to parse under the new gate without emitting any warning. Verified by including it in the gate-parser fixture.

## Dependencies & Assumptions

- **gh CLI authenticated.** `/kiln:kiln-pi-apply` depends on `gh` being authenticated against the repo's GitHub org; failure mode is a clean error + non-zero exit.
- **jq ≥ 1.6.** Frontmatter parsing and gh JSON consumption.
- **Bash 5.x.** All new scripts target Bash 5 semantics (arrays, `[[ ]]`, `$'\n'`).
- **Existing roadmap infrastructure.** `/kiln:kiln-roadmap --promote` reuses the interview engine from `specs/structured-roadmap/contracts/interfaces.md` — the helper scripts under `plugin-kiln/scripts/roadmap/` (parse-item-frontmatter.sh, validate-item-frontmatter.sh, classify-description.sh) exist and are stable.
- **Existing distill three-stream pattern.** FR-004 and FR-005 graft the gate onto the Step 1 / Step 2 flow of `plugin-kiln/skills/kiln-distill/SKILL.md`; no rewrite of the three-stream ingestion.
- **No new runtime dependency.** All work is markdown + Bash + existing `jq` / `gh` / `sha256sum` (coreutils on Linux, `shasum -a 256` on macOS — Bash shim picks the right one).

## Out of Scope (Non-Goals)

Explicit from the PRD "Non-Goals" section:

- No migration or rewrite of existing PRDs built from raw issues/feedback.
- No auto-apply of PI proposals — propose-don't-apply only.
- No changes to retrospective authoring or the `File/Current/Proposed/Why` block format.
- No changes to `/kiln:kiln-report-issue` or `/kiln:kiln-feedback` capture semantics beyond the `status: promoted` lifecycle added by FR-006.
- No hygiene subcheck for grandfathered PRDs (tracked as PRD R-5 follow-on; not in scope).
- No `--since <date>` flag on `/kiln:kiln-pi-apply` (tracked as PRD R-3 follow-on if needed).

## Risks & Mitigations (carried forward from PRD)

- **R-1 (hook loosening)** — Mitigated by the `build/*` accept being already-shipped; FR-003 fixture locks the regression boundary. Negative cases in the fixture guard FR-002.
- **R-2 (double-interviewing on `--promote`)** — Resolved by Clarification 5 (coached pre-fill from source body when body ≥ 200 chars; full interview otherwise).
- **R-3 (PI report bloat)** — `pi-hash` dedup (Clarification 7) lets subsequent reports diff cleanly. Follow-on `--since` flag if needed.
- **R-4 (stale PI anchors)** — Resolved by Clarification 6 (flag-stale only; no auto-rewrite).
- **R-5 (grandfathered PRD drift)** — Accepted as a visible exception class; follow-on hygiene subcheck tracked, not in scope here.
