# Friction Note — retrospective

**Branch**: `build/claude-audit-quality-20260425`
**Pipeline**: kiln-claude-audit-quality
**PR**: #186
**Date**: 2026-04-25

## What worked

- **Friction notes from upstream agents were uniformly substantive** — every one (researcher / specifier / impl-claude-audit / impl-tests-and-retro / auditor) shipped at least one well-anchored PI proposal already in the bold-inline `**File**/**Current**/**Proposed**/**Why**` shape. My job was synthesis, not extraction. That's the cheapest retro substrate I've seen this branch.
- **Theme F's contracts are paying off in the SAME pipeline.** I'm rating my own retro per `retro-quality.md` (the rubric this PR ships) and surfacing the score in the issue frontmatter per FR-024. The dogfood loop is closed.
- **Verbatim-Current grep -F discipline was tractable** — out of 6 candidate PIs, all 6 anchors verified via `grep -nF` on first try because upstream agents already lifted text from the target files rather than paraphrasing. PR #185 + the parser fix in `3ac305c` paid off here.

## What hit friction

### F-1 — `SendMessage` history not directly inspectable from a sub-agent shell

The team-lead's brief said "cross-reference SendMessage history — any handoff failures? misunderstandings?" but the message log isn't in a file the sub-agent can read; it lives in the harness's session memory. I had to infer handoff hygiene from (a) git log, (b) friction notes' "Coordination metadata" sections, and (c) commit-message back-references. This worked because every upstream agent did write a friction note, but it would fail catastrophically if any agent skipped one.

**Proposal**: have the team-lead drop a `specs/<feature>/agent-notes/SendMessage-log.md` (auto-generated, append-only) at end-of-pipeline so the retrospective has the actual handoff timeline. Out of scope for this PR (substrate). File as a roadmap item.

### F-2 — Concurrent-staging hazard hit upstream agents but I escaped it (one-owner phase)

Both implementer agents documented the same git-staging-area pollution incident. I'm a single-owner phase so I didn't reproduce it, but the lesson is loud enough to warrant a top-line PI in the retro. The hazard isn't agent-error — it's a structural property of "two impl agents share one branch's staging area" + "the version-increment hook stages files on every Edit/Write." See PI-1 in the retro issue.

### F-3 — No machine-readable "did this run actually meet its acceptance criteria" summary

I had to read `blockers.md` end-to-end + cross-check `## Compliance summary` table to confirm 25/25 FRs traced and 5/5 fixtures pass. A `specs/<feature>/audit-verdict.json` (auditor-emitted, single source of truth) would let the retro key off compliance numerics directly. This is a generalizable improvement, not specific to this PR.

## What I'd change about my own role

- **The retro task description is uniform across pipelines but its real shape varies a lot.** This PR shipped a self-rating rubric AS PART OF the PR, so my retro had a load-bearing self-rating obligation that prior retros didn't. The team-lead's brief did call this out ("Theme F's self-rating works"), but the coupling between "this PR adds rubric X" and "this retro must be evaluated AGAINST rubric X starting now" should be a structural part of the prompt (a "self-test against newly-shipped contracts" checklist). Not blocking; future improvement.

## Self-rating against `plugin-kiln/rubrics/retro-quality.md`

Per FR-025 + FR-024, I rate my own retrospective insight density against the three-criterion rubric:

- **Cause-and-effect**: yes — concurrent-staging hazard + version-increment hooks + shared staging area chain explained in PI-1; substrate-cache-lag chain explained in PI-3.
- **Calibration update**: yes — F-3 documents the gap in machine-readable verdict consumption; F-2 confirms the hazard is structural not error-driven.
- **Process change**: yes — 6 bold-inline PIs delivered, all with verifiable verbatim Current anchors.

Self-score: **4** ("clear cause-and-effect + calibration update + at least one process change PI delivered with verbatim-Current discipline"). Justification (≤120 chars): "6 PIs delivered with verified verbatim anchors; concurrent-staging hazard analyzed structurally."

## Coordination metadata

- Task: #6
- Started: 2026-04-25 (after auditor DM "audit complete")
- Owner: retrospective
- Output: GitHub issue (label: `build-prd,retrospective`), this friction note
- Downstream: team-lead handles cleanup
