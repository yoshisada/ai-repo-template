# Feature PRD: Kiln Structural Hygiene

**Date**: 2026-04-23
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (placeholder; product context inherited from `CLAUDE.md`)

## Background

Kiln owns two self-maintenance surfaces today: `/kiln:kiln-doctor` (validates directory structure against a manifest, migrates legacy paths, runs cheap CLAUDE.md drift checks, reports a handful of retention signals) and `/kiln:kiln-cleanup` (purges stale QA artifacts from `.kiln/qa/`). They cover two narrow slices — structural validation and artifact purge — but leave a large middle ground untouched: the broader "does this repo's layout still match what we actually want?" question. The maintainer surfaced this directly: kiln-cleanup should grow to "look for open folders, how we could improve folder structure and layout." Right now, cleanup is disproportionately scoped to QA only; the rest of the repo drifts without any tool catching it.

A concrete instance of this gap emerged this cycle: `/kiln:kiln-build-prd` Step 4b is supposed to close the loop on backlog items after their PRDs merge (flip `status: open` → `prd-created` → `completed` and archive to `.kiln/issues/completed/`). Over the last month the archive step silently failed for 18 items. Doctor didn't catch them because its `archive_completed` manifest rule deliberately only matches `status: closed|done` — it refuses to archive `prd-created` items on its own authority, since that status means "bundled into a PRD, work not yet verified complete." Cleanup didn't catch them either, because cleanup doesn't look at `.kiln/issues/` at all. The 18 items had to be manually flipped + archived in a chore commit on 2026-04-23.

This PRD treats both concerns as one story: kiln needs a **structural hygiene layer** — a tool that enforces repo-wide invariants (lifecycle completeness, folder layout, orphaned artifacts, unreferenced files) and proposes fixes for human review. The first invariant it enforces is the merged-PRD → archive flow that leaked 18 items this month.

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|-------------|--------|------|--------------|------------------|
| 1 | [Expand kiln-cleanup to audit the entire repo for structure and layout issues](../../../.kiln/feedback/2026-04-23-i-think-we-need-to.md) | `.kiln/feedback/` | feedback | — | medium / ergonomics |
| 2 | [18 stale prd-created issues never archived — build-prd Step 4b broken](../../../.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md) | `.kiln/issues/` | issue | — | high / workflow |

## Problem Statement

There is no kiln tool whose job is "audit the repo for structural and lifecycle invariants." The closest things — `/kiln:kiln-doctor` and `/kiln:kiln-cleanup` — are each scoped to one narrow slice (manifest-based directory validation, QA-artifact purge) and neither covers the gap in between: folder layout drift, orphaned files, stale-but-not-closed items, lifecycle invariants that should self-enforce. As a result, structural decay accumulates silently and only surfaces when the maintainer goes looking. The 18 stale `prd-created` items that leaked this month are the visible evidence: the invariant "a backlog item whose PRD is merged into main MUST be archived" is real and enforceable (via `gh pr view`), but no tool enforces it. Every pipeline that failed to flip these items was a silent failure — the maintainer noticed only after running doctor + manually digging.

Tactically, this manifests as 18 orphan backlog items polluting distill runs, inflating the "open work" signal in `/kiln:kiln-next`, and creating noise in Obsidian on the next vault sync. Strategically, it signals that kiln's self-maintenance story stops short of the invariants that keep the repo in a known-good shape. The fix is not to patch Step 4b and move on — it's to introduce a class of tooling that treats "repo is in the shape we agreed on" as a first-class, enforceable concern, with the merged-PRD invariant as the inaugural check.

## Goals

- **Extend `/kiln:kiln-cleanup` from its current QA-artifact scope into a general structural/invariant auditor** — folder layout, orphaned files, unreferenced artifacts, lifecycle invariants. The maintainer's "look for open folders, how we could improve folder structure and layout" becomes the MVP scope.
- **Propose, don't apply** — the new audit surfaces are a preview (diff-like or directive-list), reviewed by the maintainer before any destructive action. Mirrors `/kiln:kiln-claude-audit`'s pattern.
- **First concrete invariant: merged-PRD → archive.** For every `.kiln/issues/*.md` or `.kiln/feedback/*.md` with `status: prd-created` and a `prd:` field pointing at a PRD whose feature-branch is merged to main, propose flipping to `completed` + moving to `completed/`. The 18 items this month would have been caught by this check.
- **Integration with `/kiln:kiln-doctor`** — doctor gains a check for this new invariant class, same pattern as its CLAUDE.md drift subcheck: cheap-signals-only in doctor; full structural-hygiene analysis in the expanded cleanup.

## Non-Goals

- **No replacement of `/kiln:kiln-doctor`.** Doctor stays the manifest-validation + migration + retention-cleanup tool. The new hygiene layer sits alongside, not on top.
- **No auto-apply for destructive actions.** The merged-PRD archive is technically safe (the PRD is merged; the work is done) but still goes through a review preview — consistent with the claude-audit pattern.
- **No policy engine.** This PRD adds a finite set of invariants (defined in a rubric-style artifact), not a pluggable rule framework. Future expansion is possible but out of scope.
- **No rewriting of `/kiln:kiln-build-prd` Step 4b.** Step 4b's matching logic has a bug (confirmed by the 18 leaked items), but fixing that is not this PRD's scope. This PRD adds the *external* safety net that catches items Step 4b misses. Root-causing Step 4b's bug is a follow-on `/kiln:kiln-fix`.
- **No scope creep into CLAUDE.md** — that's owned by `/kiln:kiln-claude-audit` (already shipped in PR #141). Structural hygiene audits structure and lifecycle, not content.
- **No changes to the backlog/feedback schema.** Existing frontmatter fields are sufficient.

## Requirements

### Functional Requirements

**Structural audit expansion (feedback-derived, strategic frame)**:

- **FR-001 (from: `.kiln/feedback/2026-04-23-i-think-we-need-to.md`)** `/kiln:kiln-cleanup` (or a new sibling skill — plan phase picks the shape) MUST perform a repo-wide structural audit in addition to the current QA-artifact purge. Minimum audit scope: (a) **lifecycle invariants** (merged-PRD archival — see FR-005), (b) **orphaned top-level folders** (directories created by a prior feature but no longer referenced by any skill/agent/hook/workflow), (c) **unreferenced artifacts in `.kiln/`** (e.g., state files, outputs, lock files older than a threshold with no active workflow). Additional classes can be added later.
- **FR-002 (from: same)** The audit MUST be driven by a documented, versioned **hygiene rubric** — proposed location `plugin-kiln/rubrics/structural-hygiene.md`, same pattern as `plugin-kiln/rubrics/claude-md-usefulness.md`. Each rubric entry specifies: `rule_id`, `signal_type`, `cost` (cheap vs editorial), `match_rule`, `action` (`archive-candidate`, `removal-candidate`, `keep`, `needs-review`), `rationale`. The rubric is plugin-embedded with optional consumer override at `.kiln/structural-hygiene.config` — mirrors the CLAUDE.md audit's override pattern.
- **FR-003 (from: same)** The audit output MUST be a review preview saved to `.kiln/logs/structural-hygiene-<YYYY-MM-DD-HHMMSS>.md`, **never auto-applied**. The maintainer reviews the proposed actions, then applies them (manually, or via a follow-up `--apply` subcommand — plan phase decides). Same propose-don't-apply discipline as `/kiln:kiln-claude-audit`.
- **FR-004 (from: same)** `/kiln:kiln-doctor` MUST gain a new subcheck (naming TBD — e.g., `3h: structural hygiene drift`) that runs only the `cost: cheap` subset of the hygiene rubric, with a performance budget of **<2s**. Same shape as the existing CLAUDE.md drift subcheck. For a full audit including editorial signals, the user runs the standalone hygiene skill. Consistent with FR-004/FR-005 of the kiln-self-maintenance PRD.

**Merged-PRD archival invariant (issue-derived, tactical instance)**:

- **FR-005 (from: `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md`)** The hygiene rubric MUST include a rule `merged-prd-not-archived` that fires when all of: (a) a file under `.kiln/issues/` or `.kiln/feedback/` has `status: prd-created`, (b) its `prd:` frontmatter field points at an existing PRD file, (c) a GitHub PR whose branch matches the PRD's feature-slug is in state `MERGED` (determined via `gh pr list --state merged --search <slug>`). The proposed action is `archive-candidate` — the audit's diff preview flips `status: completed`, adds `completed_date` + `pr: #N` frontmatter, and moves the file to `completed/`.
- **FR-006 (from: same)** The rule MUST gracefully degrade when `gh` is unavailable or not authenticated: record the signal as `inconclusive` and proceed. Do not hard-fail the audit. Mirrors the existing `/kiln:kiln-next` FR-014 pattern.
- **FR-007 (from: same)** When the hygiene audit fires `merged-prd-not-archived` signals, the review preview MUST show the proposed `status: completed` + `pr: #N` + move-to-completed for each item AS A SINGLE GROUPED BLOCK (not 18 separate proposals). The maintainer accepts or rejects the block; there is no per-item cherry-pick in v1. Rationale: if the invariant holds for one item, it holds for all — per-item review is noise.
- **FR-008 (from: same)** The rule MUST NOT fire on items where the PRD path is missing (the `prd:` field is empty), malformed, or points at a PRD whose feature branch is not yet merged. Treat these as `needs-review` (maintainer-visible but not auto-archive-proposed) — gives visibility without making false claims.

**Governance and defaults**:

- **NFR-001** No new runtime dependencies. `gh` is already assumed; no new CLIs, no new MCP servers, no new libraries.
- **NFR-002** The audit MUST be idempotent — running twice on an unchanged repo produces byte-identical preview output (timestamps in the header are the only permitted difference). Same discipline the CLAUDE.md audit enforces.
- **NFR-003** Backwards compat: existing `/kiln:kiln-cleanup` invocations (with `--dry-run`, `--cleanup` mode, etc.) MUST keep working. The structural audit is an **addition**, not a replacement of current behavior.
- **NFR-004** The hygiene rubric artifact MUST be discoverable — grep for the rubric path from elsewhere (docs, README, or the skill body) returns at least one reference. Matches the claude-md rubric's discoverability requirement.

## User Stories

- **US-001** As a maintainer running `/kiln:kiln-cleanup` at the end of a cycle, I want a full-repo structural audit — not just QA artifacts — so stale folders, unreferenced files, and lifecycle drift surface for review in a single pass. (FR-001)
- **US-002** As a maintainer running `/kiln:kiln-doctor`, I want a cheap subcheck that tells me whether the repo has any structural drift, so I catch it in the normal session-start flow without needing to remember to run a separate audit. (FR-004)
- **US-003** As a maintainer who just merged a PR whose build dropped `prd-created` items on the floor, I want the next hygiene audit to catch those items and propose archiving them — without me manually greping `status: prd-created` across `.kiln/issues/`. (FR-005, FR-007)
- **US-004** As a maintainer reviewing the audit preview, I want proposed changes batched and human-reviewable, never auto-applied — so destructive moves require an explicit accept before they land. (FR-003, FR-007)

## Success Criteria

- **SC-001 Rubric exists and is versioned.** `plugin-kiln/rubrics/structural-hygiene.md` exists, contains at minimum the `merged-prd-not-archived` rule plus one rule per other Minimum audit scope category from FR-001, and is referenced from at least one non-skill location (docs, README, or CLAUDE.md).
- **SC-002 Merged-PRD archival catches a real instance.** A fixture with 2–3 `status: prd-created` items whose `prd:` points at merged PRs, plus 1 control item whose PRD is unmerged, produces a preview flagging exactly the 2–3 merged items for archive, leaving the control alone.
- **SC-003 gh-unavailable graceful degradation.** Running the audit with `gh` unset or unauthenticated produces a preview that marks `merged-prd-not-archived` signals as `inconclusive`, emits a one-line warning, and exits 0 (not a hard failure).
- **SC-004 Doctor subcheck under budget.** The new doctor subcheck runs cheap-rules-only and completes in <2s on a real-repo fixture. Measured via `/usr/bin/time -p`.
- **SC-005 Propose-don't-apply.** Grep the standalone hygiene skill's body for direct-edit / `git mv` / `sed -i` patterns on `.kiln/issues/` or `.kiln/feedback/` — zero hits. The skill writes the preview file and stops.
- **SC-006 Idempotence.** Two consecutive audit runs on an unchanged repo produce preview files with byte-identical bodies (header timestamp excluded).
- **SC-007 Backwards compat.** Existing `/kiln:kiln-cleanup --dry-run`, `/kiln:kiln-cleanup --cleanup`, and `/kiln:kiln-doctor --fix` invocations produce their pre-PRD behavior on a fixture that lacks any hygiene signals.
- **SC-008 This month's leak would have been caught.** Running the new audit against the 2026-04-23 state (pre-housekeeping-sweep — reproducible via `git checkout 574f220^`) flags all 18 stale `prd-created` items for archive. Captured as a smoke test.

## Tech Stack

Inherited from the parent product — no additions:

- Markdown (skill definitions, rubric artifact)
- Bash 5.x (audit skill body, `gh` invocation, file operations)
- `gh` CLI (already assumed) for merged-branch lookup
- `jq`, `grep`, standard POSIX utilities

## Risks & Open Questions

- **Separate skill vs extension of existing `/kiln:kiln-cleanup`.** FR-001 leaves the shape ambiguous: the work could be added as a new mode to `/kiln:kiln-cleanup` (e.g., `--audit`), or as a new sibling skill (e.g., `/kiln:kiln-hygiene` or `/kiln:kiln-audit-repo`), or both (the sibling skill IS the new mode). Plan phase must pick. Recommend a new sibling skill for clarity — extending cleanup risks muddying its existing semantics (purge vs audit are different actions).
- **gh rate limits and latency.** FR-005's `gh pr list --state merged --search <slug>` per item could burn rate limit. Plan phase should specify: one `gh pr list --state merged --limit 100` call upfront + in-memory match, rather than N gh calls. Also caches per audit run.
- **What counts as an "orphaned folder"?** FR-001 (b) is vague. Plan phase should pin the exact signal: e.g., "a top-level directory that (i) exists in neither the manifest's `directories` map nor any skill/agent/hook/workflow file-reference, AND (ii) was last modified >30 days ago". Without a sharp definition, this rule will produce false positives.
- **Bundled-accept UX (FR-007).** "All or nothing" for the archival block might frustrate a maintainer who wants to keep one item open for reasons not captured in frontmatter. Plan phase should decide: (a) strict bundle-accept (as written), (b) `--except <file>` exclusions, (c) per-item toggle. Recommend (a) for v1; revisit if it bites.
- **Naming collision with `/kiln:kiln-doctor`.** The proposed `/kiln:kiln-doctor` subcheck name (e.g., `3h`) needs to not collide with existing subcheck IDs. Spec phase must grep the current kiln-doctor SKILL.md to pick the next letter cleanly.
- **Rubric coverage at launch.** The MVP rubric has at minimum one rule per FR-001 category (merged-PRD archival, orphaned folders, unreferenced artifacts). Additional rules are welcome in the same PR but not required — rubric is designed to evolve.
- **Root-cause of Step 4b bug is still out of scope.** The issue `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md` names two classes of fix: Part A (root-cause Step 4b) and Part B (external safety net). This PRD only covers Part B. Part A remains open as a follow-on `/kiln:kiln-fix` task — the hygiene audit is the safety net, not a replacement for fixing the upstream bug.
