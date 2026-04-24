---
id: 2026-04-24-research-first-feature-track
title: "Research-first feature track — feasibility gate before build, one at a time, abandon cleanly on infeasible verdicts"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: ~3 sessions
---

# Research-first feature track — feasibility gate before build, one at a time, abandon cleanly on infeasible verdicts

## Intent

Add a feature-development mode the system can route items through when the cost of "build it wrong" is high — complex integrations, architectural additions, anything where a standard `/kiln:kiln-build-prd` run risks producing plausible-looking output that silently breaks existing assumptions. The mode runs a dedicated **feasibility investigation** upfront: "is it possible to add this cleanly given our current vision and architecture?" If yes, produce a deep design doc that the standard pipeline then anchors to. If no, document why and abandon cleanly so the attempt becomes precedent data, not lost work.

The mode is **opt-in and single-threaded by design** — only one research-first feature runs at a time, and consumption surfaces (`/kiln:kiln-distill`, `/kiln:kiln-next`) explicitly refuse to bundle or interleave them with other work. The single-threaded constraint exists to minimize blast radius — large cross-cutting changes should land in isolation so when something breaks, the cause is obvious.

## Trigger

Opt-in at capture time via a new roadmap-item frontmatter field:

```yaml
track: research-first   # opt-in; default is the standard track
```

Items with `blast_radius: infra` or `blast_radius: cross-cutting` SHOULD auto-recommend the track during the adversarial interview, but the user still has to accept — never auto-apply.

When `/kiln:kiln-build-prd` runs on an item with `track: research-first`, it routes through the research-first pipeline instead of the standard build pipeline. Non-opted items keep the existing flow. This is additive, not a replacement.

## Consumption-side enforcement (never-bundle invariant)

- **`/kiln:kiln-distill`** — refuses to bundle research-first items into a multi-theme PRD. If a research-first item matches a distill query, distill either skips it with a clear reason or offers to run distill on it alone (one item → one PRD).
- **`/kiln:kiln-next`** — surfaces research-first items as **isolated recommended actions**, never alongside other items. Rendered as a standalone bullet with a note: "research-first track — run alone."
- **`/kiln:kiln-roadmap --check`** — flags when two or more research-first items have `state: specced` or `state: in-phase` simultaneously (violates the one-at-a-time invariant).

## Pipeline shape

The research-first pipeline has three stages; the standard pipeline only kicks in after stage 2 yields a "yes" verdict.

### Stage 1 — Feasibility investigation ("is it possible to add cleanly?")

A dedicated agent (or short agent team) investigates:
- Every existing touchpoint the feature would interact with (consumes the `precedent-reader` helper from `2026-04-24-precedent-reader-helper`).
- Backward-compat implications for existing consumers (via `install-smoke-ci` style thinking).
- Architectural assumptions that would have to hold or shift.
- Known constraints from `.kiln/roadmap/items/` entries with `kind: constraint` or `kind: non-goal`.
- Vision alignment (`/kiln:kiln-vision` content).

Output: a structured verdict document at `docs/research/<slug>/feasibility.md`:
- `verdict: yes | no | conditional`
- For `conditional`: the preconditions (e.g., "feasible after upgrading dependency X" or "feasible if we accept a one-time migration").
- For `no`: a `blocked_reason:` narrative — what would need to change to revisit, architectural/dependency/vision-level blockers, specific things to try if the user wants to retry later.

### Stage 2 — Deep design (only on yes / conditional)

On `yes` or `conditional`, the pipeline produces `docs/research/<slug>/design.md` covering:
- How the feature integrates with every existing touchpoint identified in Stage 1.
- Backward-compat and migration plan for existing consumers.
- Specific failure modes and how the design prevents them (not "what could go wrong" — "what does the design do to prevent each").
- Explicit integration test surface — not just happy path, but what the feature breaks if done wrong.
- Rollback plan — if this ships and is wrong, what does reversing it require?

The standard `/kiln:kiln-build-prd` pipeline then runs on top, anchored to `design.md` rather than starting from a blank frame.

### Stage 3 — Standard pipeline (build-prd)

No changes to `/kiln:kiln-build-prd` itself — it receives the item + the design doc as enriched input context. Spec, plan, tasks, implementation all lean on the design doc as the authoritative "how."

## Verdict-driven state transitions

On `verdict: no` from Stage 1, the pipeline:
1. **Flips the item's frontmatter** to `status: blocked` with `blocked_reason:` pointing at `docs/research/<slug>/feasibility.md`. The item is NOT auto-flipped to `kind: non-goal` — that's a human judgement about permanent decline vs deferral.
2. **Abandons the feature branch cleanly** — if a branch was created for this attempt, the pipeline:
   - Commits any research artifacts (feasibility.md, any exploratory notes) to the branch.
   - Pushes the branch with a `status/abandoned` label or similar marker.
   - Returns the working tree to the base branch.
   - Records the abandoned attempt in the item's frontmatter:
     ```yaml
     abandoned_attempts:
       - date: 2026-04-24
         branch: research/research-first-feature-track-attempt-1
         verdict: no
         reason: <summary>
         feasibility_doc: docs/research/research-first-feature-track/feasibility.md
     ```
3. **Leaves the item available to retry later.** The next time `/kiln:kiln-next` surfaces this item, it shows the `blocked_reason` and lists prior abandoned attempts so the user can decide: research more, fix the blocker, or explicitly mark as `kind: non-goal`.

On `verdict: conditional`, the pipeline pauses and surfaces the preconditions to the user — they either accept and proceed to Stage 2, or abandon with the conditions documented.

On `verdict: yes`, pipeline continues to Stage 2 without interruption.

## Failure modes to avoid

- **Opt-in drift** — if every feature eventually gets tagged `track: research-first`, the one-at-a-time invariant becomes a bottleneck. Keep the default track standard; research-first is reserved for genuinely high-stakes additions.
- **Feasibility theater** — producing a `verdict: yes` feasibility doc that's actually just a restatement of the feature description isn't a feasibility check. The stage 1 agent must ground its verdict in concrete touchpoints, not generalities. Prior abandoned attempts on similar items (via precedent-reader) are a strong tell that a verdict is too optimistic.
- **Abandoned-branch orphaning** — if a branch is abandoned but not actually cleaned up (still consumes CI time, still shows in open-PR lists), the discipline erodes. Pair the abandon with explicit branch-lifecycle handling.
- **Retry fatigue** — if an item has 3+ abandoned attempts, the system should surface that and ask the user whether to flip to `kind: non-goal` explicitly rather than silently letting retry cycles accumulate.

## Dependencies

- **`2026-04-24-precedent-reader-helper`** — the feasibility stage consumes precedent heavily (prior decisions, declined non-goals, feedback on related features). Research-first would be much weaker without it.
- **`2026-04-24-code-review-team-with-static-analysis`** — the design doc produced by Stage 2 is input to the review team; the review team checks whether the implementation matches the design, not just the spec.
- **Existing `/kiln:kiln-build-prd` pipeline** — no structural changes required, but it needs to accept the design doc as enriched input context.
- **Roadmap item frontmatter schema** — needs to accept the new `track:`, `blocked_reason:`, `abandoned_attempts:` fields; validator needs to tolerate them without treating as forbidden.

## Success signal

- Research-first items ship with fewer post-merge bug fixes than standard-track items of comparable complexity — measurable via "human-requested-changes rate" and "fix-skill invocations per feature."
- Abandoned attempts don't rot — the feasibility docs they produce are referenced in future precedent queries, not forgotten. The precedent-reader surfaces them when the user captures a new item that's similar to a prior abandoned attempt.
- The "one at a time" invariant holds in practice — no two research-first items are ever in `state: in-phase` simultaneously without explicit user override.

## Relation to vision

Directly supports the "senior-engineer-merge bar" commitment (§1, §3) for the highest-stakes features — complex/architectural additions get the design scrutiny they deserve. Also reinforces "context-informed autonomy" (§4) by making abandoned attempts first-class precedent, so the system doesn't re-attempt the same infeasible directions.
