---
id: 2026-04-27-auto-flip-on-async-merge
title: "Auto-flip on async merge — Step 4b.5 doesn't fire when user merges PR after team-lead shutdown"
kind: feature
date: 2026-04-27
status: open
phase: 90-queued
state: planned
blast_radius: feature
review_cost: moderate
context_cost: "1 session"
---

# Auto-flip on async merge — Step 4b.5 doesn't fire when user merges PR after team-lead shutdown

## Context

Theme A of escalation-audit (PR #189) shipped Step 4b.5 in `kiln-build-prd/SKILL.md` as an inline bash block that auto-flips roadmap items on PR merge. It works correctly when invoked — verified live in the same session: revert items, run the verbatim Step 4b.5 bash block against merged PR #189, observe `step4b-auto-flip: pr-state=MERGED auto-flip=success items=3 patched=3`, re-run for `already_shipped=3` (FR-004 idempotency).

But in actual usage, Step 4b.5 only fires INSIDE an active build-prd pipeline run. The common case is: build-prd ships the PR, the team shuts down, the maintainer merges asynchronously some time later. By the time the merge happens, the team-lead context is gone — Step 4b.5 has nothing to execute it. Items stay at `state: distilled` until manually flipped.

This was the original drift PR #186 captured (8 items needing manual flip), and ironically PR #189 itself hit the same gap — I had to manually run the just-shipped Step 4b.5 logic to verify SC-006.

## Suggested fixes (pick one)

- **(a) merge-watcher hook** — git/gh hook that detects merged PRs whose head branch matches `build/<slug>-<YYYYMMDD>`, finds the matching PRD by frontmatter, runs the Step 4b.5 logic. Most automatic but most invasive.
- **(b) standalone `/kiln:kiln-flip-on-merge <pr>` skill** — user invokes after async merge; the skill runs the Step 4b.5 logic. Cheapest to build (extract the existing bash block to a shared script + thin SKILL.md wrapper). Requires user discipline.
- **(c) `/kiln:kiln-roadmap --check` tripwire fix-mode** — FR-005 of escalation-audit already detects this drift; extend `--check` with `--fix` that offers to flip detected drift one-shot. Most aligned with existing tripwire pattern. Also covers historical drift, not just future.

Recommendation: ship **(b) + (c)** together — (b) for the immediate post-merge case, (c) for catch-up on historical drift. Both consume a shared `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` helper extracted from the current Step 4b.5 inline block.

## Why this matters

The whole point of Theme A was "no manual sweeps." If the auto-flip only fires inside build-prd, and build-prd shuts down before merge, the manual sweep just moves to a different point in the timeline.

## Evidence

- PR #189 session log: had to extract Step 4b.5 from cached plugin 000.001.009.816 and run standalone to verify SC-006
- Commits: 1c55419d (manual flip with wrong format), 22a91b10 (re-flip via shipped Step 4b.5 bash block)
- Discussion in PR #189 session 2026-04-26 between team-lead and user

## Addresses

- Drift loop captured in `2026-04-25-build-prd-auto-flip-item-state` (now shipped, but PR-merge timing edge case missed in scope)
