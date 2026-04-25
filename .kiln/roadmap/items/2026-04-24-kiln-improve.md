---
id: 2026-04-24-kiln-improve
title: /kiln:kiln-improve — auto-route GH issues into roadmap/feedback/issues
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: "2-4 sessions"
depends_on:
  - 2026-04-23-add-support-for-defining-what
  - 2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents
  - 2026-04-24-precedent-reader-helper
implementation_hints: |
  Wheel workflow (verified: loops + WORKFLOW_PLUGIN_DIR for command/loop steps).
  Outer loop pops oldest issue from /tmp/issue-queue.json (built from `gh issue list --state open --json ...`).
  Per-issue substeps (sequential):
    1. freshness-check (command, no LLM): grep .kiln/issues/completed/, git log --grep=#<num>, scripted reproduction probe for "X breaks when Y" patterns.
    2. atomic-extract (Haiku agent): split body into atomic items — File/Current/Proposed/Why blocks, enumerated proposals, narrative paragraphs.
    3. motivation-classify (Haiku agent): each atomic item → motivation → surface (deterministic table).
    4. capture (command): invoke /kiln:kiln-report-issue / /kiln:kiln-feedback / /kiln:kiln-roadmap with source: <gh-url> + source_block: <line-range>.
    5. summarize-and-close (command): `gh issue comment` with capture list; `gh issue close` if all atomic items routed cleanly AND freshness-check confirmed reproducibility.
  Inconclusive routing → kind:research with "needs reproduction or telemetry to classify" note.
  Bound on N via .shelf-config key `improve_max_issues_per_run` (default: 5). Same pattern as `shelf_full_sync_threshold`.
  Idempotency: capture's `source: <gh-url>` field is the dedup key; second run skips already-routed issues. `source_block:` allows partial-routing (re-run picks up new content added to an already-touched issue).
  Cheaper-first sequencing: ship without atomic-extract + auto-close in v1; layer those in v2.
  Deprecate /kiln:kiln-pi-apply skill wrapper — keep `parse-pi-blocks.sh` + `compute-pi-hash.sh` as helpers under `plugin-kiln/scripts/pi-apply/`.
  Deprecate /kiln:kiln-analyze-issues with redirect stub for one release cycle.
  Surface in /kiln:kiln-next when count of un-routed open GH issues exceeds threshold (default: 3).
---

# /kiln:kiln-improve — auto-route GH issues into roadmap/feedback/issues

A wheel workflow that ingests open GitHub issues, classifies their content into atomic items, and routes each one to the appropriate capture surface (`/kiln:kiln-report-issue`, `/kiln:kiln-feedback`, or `/kiln:kiln-roadmap`) — with `source: <gh-url>` back-references that satisfy the roadmap-first intake gate (FR-004 of `workflow-governance`). Replaces the manual triage step that nobody actually performs.

## Hardest part

Motivation classification — deterministic mapping from motivation (not wording) to surface, while keeping it cheap enough to run as a Haiku subagent without user prompts. This is the one step that could silently misroute things; everything else is bash plumbing or `gh` CLI calls.

## Key assumption

(a) Freshness checks can be done deterministically via `grep .kiln/issues/completed/`, `git log --grep`, and scripted reproduction probes — no LLM needed.
(b) Haiku is sufficient for atomic-block extraction + motivation classification.

If either fails, the cost story collapses and the workflow needs per-step model selection (which is itself the HARD dependency).

## Depends on

- `2026-04-23-add-support-for-defining-what` — **HARD**: per-step model selection in workflows. Without it, the whole workflow runs on one model. Workaround: ship with everything-on-Haiku.
- `2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents` — **SOFT**: `WORKFLOW_PLUGIN_DIR` is verified exported for `command` and `loop` substeps but not for bg subagents spawned from `agent` steps. Workaround: author the workflow with command-step capture invocations and inline subagents (no bg fan-out).
- `2026-04-24-precedent-reader-helper` — **SOFT**: needed for context-informed close decisions (auto-close based on prior `kind:non-goal` precedent rather than user prompt). Workaround: surface low-confidence close decisions to user.

Future link (after promotion): `addresses:` retro-#160's "retros never get applied" critique once `/kiln:kiln-improve` itself is used to promote that finding from issue → critique.

## Cheaper 80% version

Ship v1 without auto-close and without atomic-block extraction:

- Route whole GH issues as single units to one surface (the dominant motivation wins).
- Maintainer manually splits multi-intent issues later.
- Pi-apply's `parse-pi-blocks.sh` is reused only for the "is this a retro PI?" detection, not the full extract-and-route fan-out.

This delivers the routing-loop + freshness-check + capture-with-source value (the hardest behavioral change) without the LLM-heavy extraction step. v2 adds per-block routing and auto-close.

## Breaks if deps slip

- **Per-step model not ready** → ship with Haiku-everywhere. Accept the model lock; revisit when per-step lands. No correctness risk, just bounded flexibility.
- **`WORKFLOW_PLUGIN_DIR` not fixed** → use sequential command-step capture invocations (one issue at a time, no bg fan-out). Slower (no parallelism across issues) but functionally complete.
- **retro-#160 critique not promoted** → ship without `addresses:` field, link via prose in the body. `--check` will not flag a dangling reference because none exists.
- **Precedent-reader not ready** → close decisions surface to user instead of auto-closing. Loses some autonomy; doesn't break the workflow.

## Surface alignment with `workflow-governance` (just shipped)

This item is the natural consumer of the roadmap-first intake we just shipped in PR #159:

- `/kiln:kiln-improve` produces captures that all carry `source: <gh-url>` — satisfying FR-004's "no PRD content from raw sources without promotion" gate by construction.
- The retro-PI extraction logic (just shipped as `/kiln:kiln-pi-apply`) becomes an internal subroutine of `/kiln:kiln-improve`'s atomic-extract step. The standalone skill wrapper gets deprecated.
- `/kiln:kiln-next` (FR-013 of workflow-governance) gains an analogous surfacing rule: when un-routed open GH issues exceed threshold, suggest `/kiln:kiln-improve`.

## Open questions for `/plan` phase

- Atomic-block granularity rule for prose-only retros (no explicit File/Current/Proposed/Why blocks) — split on enumeration markers or treat as one item?
- `--no-close` flag default — auto-close on clean routing, or always require maintainer to close manually?
- Does `improve_max_issues_per_run` apply per invocation or per day? (Per-invocation is simpler; per-day requires state.)
- Migration path for `/kiln:kiln-analyze-issues` users — deprecation banner duration, redirect stub vs. hard-remove cadence.
