---
id: 2026-04-27-auto-flip-on-async-merge
title: "Auto-flip on async merge — Step 4b.5 doesn't fire when user merges PR after team-lead shutdown"
kind: feature
date: 2026-04-27
status: open
phase: 90-queued
state: distilled
blast_radius: feature
review_cost: moderate
context_cost: "1 session"
prd: docs/features/2026-04-27-merge-pr-and-sc-grep-guidance/PRD.md
---

# Auto-flip on async merge — Step 4b.5 doesn't fire when user merges PR after team-lead shutdown

## Context

Theme A of escalation-audit (PR #189) shipped Step 4b.5 in `kiln-build-prd/SKILL.md` as an inline bash block that auto-flips roadmap items on PR merge. It works correctly when invoked — verified live in the same session: revert items, run the verbatim Step 4b.5 bash block against merged PR #189, observe `step4b-auto-flip: pr-state=MERGED auto-flip=success items=3 patched=3`, re-run for `already_shipped=3` (FR-004 idempotency).

But in actual usage, Step 4b.5 only fires INSIDE an active build-prd pipeline run. The common case is: build-prd ships the PR, the team shuts down, the maintainer merges asynchronously some time later. By the time the merge happens, the team-lead context is gone — Step 4b.5 has nothing to execute it. Items stay at `state: distilled` until manually flipped.

This was the original drift PR #186 captured (8 items needing manual flip), and ironically PR #189 itself hit the same gap — I had to manually run the just-shipped Step 4b.5 logic to verify SC-006.

## Decided direction — ship (b) + (c)

User confirmed 2026-04-27: ship **(b) + (c)** together. Specifically, (b) should be a **"merge-and-flip"** skill — the skill DOES the merge itself (not just react after-the-fact). User invokes `/kiln:kiln-merge-pr <pr>` (working name); the skill calls `gh pr merge`, waits for merge confirmation, then runs the Step 4b.5 auto-flip logic atomically. This collapses two manual steps (merge + flip) into one command and eliminates the async-merge gap by construction — the moment the merge succeeds, the flip runs.

### (b) `/kiln:kiln-merge-pr <pr>` — merge + auto-flip combined skill (PRIMARY)

- Inputs: `<pr>` (number) — required.
- Flags: `--squash | --merge | --rebase` (default: `--squash` matching team convention); `--no-flip` escape hatch (merge only, skip auto-flip)
- Steps:
  1. `gh pr view <pr> --json state,mergeable,mergeStateStatus` — gate on CLEAN/MERGEABLE
  2. `gh pr merge <pr> --squash --delete-branch` (or whatever flag the user passed)
  3. Wait for merge confirmation via `gh pr view <pr> --json state,mergedAt --jq '.state'`
  4. Locate the PRD via `gh pr view <pr> --json files` → find `docs/features/*/PRD.md` touched
  5. Run the shared `auto-flip-on-merge.sh` helper against that PRD's `derived_from:` list
  6. Emit the canonical `step4b-auto-flip:` diagnostic line
  7. Commit + push the roadmap-item flips

### (c) `/kiln:kiln-roadmap --check --fix` — tripwire catch-up (SECONDARY)

- FR-005 of escalation-audit already detects drift; extend `--check` with `--fix` that one-shot flips detected drift after user confirmation
- Catches historical drift (items that drifted before this skill shipped, or PRs merged via the GitHub web UI / another flow that bypassed `/kiln:kiln-merge-pr`)
- Confirm-never-silent: list the drifted items, ask `[fix all / pick / skip]`, fire `auto-flip-on-merge.sh` for accepted entries

### Shared helper extraction

Both (b) and (c) consume `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`, extracted verbatim from the existing Step 4b.5 inline block. Step 4b.5 in `kiln-build-prd/SKILL.md` should be refactored to also call this helper — pure extraction, no behavior change. This means the same logic is reachable from three call sites: in-pipeline (Step 4b.5), out-of-pipeline-merge (b), historical-drift catch-up (c).

### Rejected alternative

- **(a) merge-watcher hook** — git/gh hook that detects merged PRs out-of-band. Rejected: too invasive (cross-cutting hook surface), and (b)+(c) cover the same ground with less infrastructure.

## Why this matters

The whole point of Theme A was "no manual sweeps." If the auto-flip only fires inside build-prd, and build-prd shuts down before merge, the manual sweep just moves to a different point in the timeline.

## Evidence

- PR #189 session log: had to extract Step 4b.5 from cached plugin 000.001.009.816 and run standalone to verify SC-006
- Commits: 1c55419d (manual flip with wrong format), 22a91b10 (re-flip via shipped Step 4b.5 bash block)
- Discussion in PR #189 session 2026-04-26 between team-lead and user

## Addresses

- Drift loop captured in `2026-04-25-build-prd-auto-flip-item-state` (now shipped, but PR-merge timing edge case missed in scope)
