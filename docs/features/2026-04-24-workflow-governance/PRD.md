---
derived_from:
  - .kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md
  - .kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md
  - .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md
distilled_date: 2026-04-24
theme: workflow-governance
---
# Feature PRD: Workflow Governance — Pipeline Integrity & Feedback Loop

**Date**: 2026-04-24
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

The kiln pipeline is self-referential: `/kiln:kiln-build-prd` produces artifacts (retros, audits, blockers) that describe how the pipeline itself behaved, and those artifacts are meant to feed back into skill/hook source to make future runs better. Three current gaps break that feedback loop and let work slip through ungoverned.

First, the pipeline's own branch-naming convention (`build/<slug>-<YYYYMMDD>`) is rejected by `require-feature-branch.sh`, which only whitelists `###-` and `YYYYMMDD-HHMMSS-` prefixes. Every pipeline teammate — specifier, implementer, auditor, retrospective — trips the hook when writing to `specs/<feature>/`, forcing Bash/Python workarounds that deviate from the spec.

Second, `/kiln:kiln-distill` accepts raw issues and feedback as direct PRD sources. That means tactical bug reports and strategic notes bypass the roadmap's classification pipeline — no `kind:`, no `blast_radius` / `review_cost` / `context_cost` sizing, no adversarial interview, and no precedent-tracking shape. The governance claim in capture #2026-04-24-prd-requires-roadmap-item-source is that the roadmap is the canonical intake for PRD creation, and issues/feedback should be *promotion sources*, not direct inputs.

Third, retrospective issues (#147, #149, #152) contain concrete `File/Current/Proposed/Why` prompt rewrites that never get pulled back into `plugin-kiln/skills/**/SKILL.md` or `plugin-kiln/agents/**.md`. The same PIs get re-proposed pipeline after pipeline (PI-1 is now at 5 stable occurrences). Retrospective work documents drift rather than driving improvement.

Together these three gaps make the pipeline simultaneously (a) unable to write its own artifacts without hook fights, (b) willing to accept ungoverned input, and (c) unable to commit its own learnings. This PRD closes all three.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [require-feature-branch.sh blocks specs/ writes on build/* branches](.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md) | .kiln/issues/ | issue | — | high / hooks |
| 2 | [PRDs must trace back to a roadmap item — distill requires roadmap-item sources](.kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md) | .kiln/issues/ | issue | — | medium / governance |
| 3 | [Retrospective-proposed prompt improvements never get pulled back into the source tree](.kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md) | .kiln/issues/ | issue | — | medium / workflow |

## Problem Statement

The pipeline cannot govern itself. Its own branch-naming scheme is rejected by its own branch hook; its own PRD-distill step accepts inputs that bypassed the governing roadmap-sizing layer; and its own retrospectives generate actionable prompt improvements that then sit unread in GitHub issue bodies. Each of these individually is a small defect. Collectively they tell the same story: kiln produces governance artifacts about itself but has no mechanism to feed them back into enforcement.

## Goals

- **Unblock pipeline writes** — `/kiln:kiln-build-prd` must be able to write to `specs/<feature>/` on its `build/<slug>-<YYYYMMDD>` branches without any teammate tripping `require-feature-branch.sh`.
- **Enforce roadmap-first intake** — `/kiln:kiln-distill` must require that every PRD trace back to a roadmap item; raw issues/feedback are promotion sources, not direct PRD inputs.
- **Provide a promotion path** — a first-class way to move an issue or feedback note into a properly-classified roadmap item (kind, sizing, adversarial interview, `promoted_from:` back-reference).
- **Close the retro → source loop** — a propose-don't-apply mechanism that extracts `File/Current/Proposed/Why` PI blocks from retro issues and emits a human-reviewable diff preview under `.kiln/logs/`.
- **Preserve backward compatibility** — previously-distilled PRDs built from raw issues are grandfathered; the change is forward-looking only.

## Non-Goals

- This PRD does NOT migrate or rewrite existing PRDs that were built from raw issues/feedback (per capture #2026-04-24-prd-requires-roadmap-item-source: "existing distilled PRDs do not need retroactive fixing").
- This PRD does NOT auto-apply PI proposals from retros — only propose-don't-apply. Maintainer still reviews and commits.
- This PRD does NOT redesign retrospective authoring or change the `File/Current/Proposed/Why` block format; it only adds a downstream extractor.
- This PRD does NOT touch `/kiln:kiln-report-issue` or `/kiln:kiln-feedback` capture semantics beyond adding a status lifecycle (`open` → `promoted`).

## Requirements

### Functional Requirements

**Hook accept-list expansion**
- **FR-001** *(from: .kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md)* — `plugin-kiln/hooks/require-feature-branch.sh` MUST accept `build/<slug>-<YYYYMMDD>` as a valid feature branch and allow `Write` / `Edit` against `specs/<slug>/` without blocking. The hook's allow-list pattern MUST be extended to include `build/*` (matching any branch whose name starts with `build/`).
- **FR-002** *(from: .kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md)* — The hook MUST continue to reject bare `main`, `master`, and unprefixed feature branches; expansion is scoped to `build/*` only. Existing `###-` and `YYYYMMDD-HHMMSS-` patterns remain valid.
- **FR-003** *(from: .kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md)* — A shell test under `plugin-kiln/tests/` (or equivalent) MUST exercise the hook against a simulated `build/workflow-governance-20260424` branch name and assert an exit code of 0 for a write path under `specs/workflow-governance/`.

**Roadmap-first PRD intake**
- **FR-004** *(from: .kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md)* — `/kiln:kiln-distill` MUST refuse to bundle raw issues or feedback that have not been promoted to roadmap items. When the user-selected theme contains only un-promoted sources, the skill MUST NOT emit a PRD; it MUST instead surface the un-promoted entries and offer the promotion path.
- **FR-005** *(from: .kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md)* — `/kiln:kiln-distill` MUST offer a confirm-never-silent promotion hand-off at theme-selection time: "Issues X and feedback Y aren't yet roadmap items; promote them before distilling?" with per-entry accept/skip. User-declined entries are excluded from the distill run; accepted entries are routed through `/kiln:kiln-roadmap --promote` and then re-read into the distill bundle.
- **FR-006** *(from: .kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md)* — `/kiln:kiln-roadmap --promote <issue-id-or-path>` MUST exist as a first-class invocation that:
  - Reads the source issue or feedback file
  - Runs the adversarial interview (FR-015 of `structured-roadmap`) against the source material with coached suggestions
  - Classifies `kind:` (feature / goal / research / constraint / non-goal / milestone / critique)
  - Captures `blast_radius`, `review_cost`, `context_cost`, and `phase:`
  - Writes a new `.kiln/roadmap/items/<date>-<slug>.md` with `promoted_from: <source-path>` in its frontmatter
  - Updates the source entry's frontmatter to `status: promoted` and adds `roadmap_item: <item-path>` back-link
- **FR-007** *(from: .kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md)* — Distill's three-group `derived_from:` sort (feedback → item → issue) MUST be preserved as a *shape* even when the feedback and issue groups are empty in practice. This keeps the frontmatter contract stable and lets grandfathered PRDs continue to parse.
- **FR-008** *(from: .kiln/issues/2026-04-24-prd-requires-roadmap-item-source.md)* — Pre-existing PRDs that cite raw issues/feedback in their `derived_from:` lists MUST continue to validate and parse; no migration is triggered on them. Enforcement is forward-looking from the PRD's `distilled_date`.

**Retro → source feedback loop**
- **FR-009** *(from: .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md)* — A new `/kiln:kiln-pi-apply` skill MUST read GitHub retrospective issues (filter: `label:retrospective`), extract every `File / Current / Proposed / Why` block, and emit a single consolidated diff-preview report at `.kiln/logs/pi-apply-<timestamp>.md`.
- **FR-010** *(from: .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md)* — The report MUST be propose-don't-apply: it renders unified-diff-shaped patches against `plugin-kiln/skills/**/SKILL.md` and `plugin-kiln/agents/**.md` but never writes to those files. Same discipline as `/kiln:kiln-claude-audit` and `/kiln:kiln-hygiene`.
- **FR-011** *(from: .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md)* — Each PI block in the report MUST include:
  - Source issue URL + PI identifier (e.g. `#149 PI-1`)
  - Target file + target heading/section anchor
  - Proposed diff
  - The retro author's "Why" verbatim
  - A stable `pi-hash` so re-runs can detect whether an unapplied proposal has already been surfaced in a prior report (dedup hint for human reviewer).
- **FR-012** *(from: .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md)* — The skill MUST skip PI blocks whose target file + anchor already contain the proposed text verbatim (already applied). It MUST mark stale PIs whose anchor no longer exists in the source tree (structural drift since the retro).
- **FR-013** *(from: .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md)* — `/kiln:kiln-pi-apply` MUST be discoverable from `/kiln:kiln-next` as a queued maintenance task when the count of open retro issues with unresolved PIs exceeds a threshold (default: 3 PIs).

### Non-Functional Requirements

- **NFR-001** — `require-feature-branch.sh` changes MUST NOT slow the hook by more than 50ms on a typical repo (`git branch --show-current` + regex match). Measure before and after.
- **NFR-002** — `/kiln:kiln-pi-apply` MUST complete within 60 seconds for a repo with ≤20 open retro issues. GitHub API calls use `gh` CLI with appropriate caching.
- **NFR-003** — Promotion (`/kiln:kiln-roadmap --promote`) MUST preserve the source file's byte content except for the frontmatter status and back-reference fields. No reflow, no body edits.
- **NFR-004** — All three changes MUST be independently releasable (hook fix, distill gate, pi-apply skill). No cross-dependency that forces bundled rollout.
- **NFR-005** — Backward compatibility: previously-distilled PRDs with raw-issue `derived_from:` entries MUST continue to parse and validate without warning under the new gate.

## User Stories

- As a **pipeline operator running `/kiln:kiln-build-prd`**, I want every spawned teammate to be able to write to `specs/<feature>/` without hitting the branch hook, so that the pipeline completes without Bash/Python workarounds.
- As a **maintainer triaging open issues**, I want a dedicated promotion path so that a tactical bug report becomes a properly-classified roadmap item with sizing and interview history before it influences a PRD.
- As a **distiller selecting a theme for a PRD**, I want the skill to refuse un-promoted inputs (or offer to promote them) so that every PRD I ship traces to a roadmap item with a consistent shape.
- As a **retrospective reviewer**, I want a single `.kiln/logs/pi-apply-*.md` report that consolidates every unresolved PI from open retro issues so that I can review and apply them in one sitting instead of re-reading three separate GitHub issues.
- As a **future auditor**, I want retro-proposed R-1 language to eventually land in the auditor's SKILL.md so that each new auditor doesn't re-discover R-1 by reading prior friction notes.

## Success Criteria

- **SC-001** — After rollout, a fresh `/kiln:kiln-build-prd` run on a non-trivial feature completes end-to-end with zero `require-feature-branch` hook blocks logged in `.kiln/logs/`.
- **SC-002** — `/kiln:kiln-distill` refuses a run whose bundle contains only un-promoted issues and surfaces the promotion prompt. Measured: a dry-run invocation on the current theme 2 backlog (3 open issues, 0 items) produces the "promote these first?" dialog and exits cleanly when the user declines.
- **SC-003** — `/kiln:kiln-roadmap --promote <issue-path>` produces a valid `.kiln/roadmap/items/<date>-<slug>.md` with `kind:`, all three sizing fields, `phase:`, and `promoted_from:`; the source issue's frontmatter is updated to `status: promoted` + `roadmap_item:`.
- **SC-004** — Running `/kiln:kiln-pi-apply` on the current retro backlog (#147, #149, #152) produces a `.kiln/logs/pi-apply-<timestamp>.md` listing at minimum PI-1 (R-1 auditor blessing), PI-2 (FR-005 collision), and the version-bump drift item, with deduplication: a second run within the same day emits byte-identical output when no retros have changed.
- **SC-005** — The PI-1 proposal specifically (R-1 "strict behavioral superset" blessing, 5 stable occurrences across retros #147/#149/#152) is surfaced in the first `/kiln:kiln-pi-apply` report with the correct target file `plugin-kiln/agents/prd-auditor.md` and a unified-diff patch.

## Tech Stack

Inherited from the parent repo:

- Bash 5.x + `jq` for hook changes, promotion script, and pi-apply extraction
- `gh` CLI for retro issue ingestion
- Markdown skill/agent definitions (no new runtime dependency)
- YAML frontmatter via existing `plugin-kiln/scripts/roadmap/parse-item-frontmatter.sh` pattern
- Existing three-group deterministic sort convention (`LC_ALL=C sort`) for any list emission

No new dependencies.

## Risks & Open Questions

- **R-1** — Expanding `require-feature-branch.sh` to accept `build/*` unconditionally loosens the "feature-branch discipline" invariant. **Mitigation**: the `build-prd` skill itself enforces the `build/<slug>-<YYYYMMDD>` format when creating the branch, so the hook loosening doesn't create a real new surface for accidental main-branch work.
- **R-2** — Auto-promotion from raw issues risks double-interviewing when the issue was captured with substantial detail already. **Open question**: should `--promote` short-circuit the interview if the source already has a filled-out "why / proposed acceptance" block? Provisional answer: offer the same "accept-all / tweak-then-accept" coaching pattern used by `/kiln:kiln-roadmap` (per `feedback_interview_pacing` memory); present inferred kind + sizing + interview skeleton as defaults, let the user confirm or tweak in pairs.
- **R-3** — The PI-apply report could grow unwieldy if retros accumulate. **Mitigation**: `pi-hash` deduplication (FR-011) lets subsequent reports highlight only new-or-changed proposals. If that's insufficient, add `--since <date>` flag in a follow-on.
- **R-4** — Structural drift invalidates PI anchors (FR-012). **Open question**: do we want an auto-rewrite-anchor pass, or strictly propose-and-flag-stale? Provisional answer: flag-stale only; maintainer applies with judgment. Auto-rewriting anchors risks producing subtly wrong diffs.
- **R-5** — Grandfathered PRDs (NFR-005) mean the "roadmap-first" invariant has a visible exception class. **Open question**: should a future `/kiln:kiln-hygiene` subcheck list grandfathered PRDs so the exception doesn't quietly expand? Probably yes — track as a follow-on, not in scope here.

## Implementation Notes (non-binding)

- FR-001 / FR-002 / FR-003 together are a one-line hook change plus a test fixture. Prioritize: highest severity and smallest scope of the three sub-initiatives — ship first, independently.
- FR-004 through FR-008 hang together: the distill gate + promotion path are a single coherent behavior change. Sequence: promote-path first (so the gate has a viable escape hatch), then flip the gate.
- FR-009 through FR-013 are substantive new skill work. Consider scaffolding `/kiln:kiln-pi-apply` as a thin `gh issue list` + regex-extractor MVP first, then layer on `pi-hash` dedup and `/kiln:kiln-next` integration.
- Each of the three sub-initiatives can be its own pipeline run under `/kiln:kiln-build-prd` (they are independently releasable — NFR-004).
