---
id: 2026-04-24-git-worktrees-value-investigation
title: "Investigate Superhuman-style git worktree workflow — does it actually add value to our development cycle?"
kind: research
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: isolated
review_cost: trivial
context_cost: ~1 session
---

# Investigate Superhuman-style git worktree workflow — does it actually add value to our development cycle?

## The decision this unblocks

Whether to adopt git worktrees as the default isolation primitive for parallel agent work. Today `/kiln:kiln-build-prd` runs pipelines on a single working tree with branch-switching; the just-captured research-first-feature-track item (`2026-04-24-research-first-feature-track`) enforces a one-at-a-time invariant partly because switching branches mid-pipeline is fragile.

If worktrees fit this project cleanly, we could:

- Run multiple `/kiln:kiln-build-prd` pipelines in parallel worktrees without `.wheel/` state interference.
- Keep abandoned research-first-track branches isolated in their own worktrees for later inspection without polluting the main checkout.
- Let agents experiment in throwaway worktrees without touching the primary working tree.
- Context-switch faster during development — jump between an in-flight PRD and a bug fix without `git stash` ceremony.

If worktrees don't meaningfully add value, we keep the current single-checkout + branch-switching model and invest that effort elsewhere.

## Framing — value first, feasibility second

Open the investigation by asking **"does this actually add anything to our development cycle?"** — faster iteration? more parallelizable agent pipelines? isolated abandoned-attempt branches? cheaper context switching? Concretely compare the current single-checkout flow vs the worktree flow in 3-4 representative day-to-day scenarios.

If the value story is thin or neutral, the investigation **stops there** — no integration plan, no prototype. Only commit to the technical feasibility work if the value story holds up.

This sequencing is deliberate: avoid writing a detailed integration plan for a pattern that turns out to be neutral or negative for our flow.

## Scope of the investigation

The output doc at `docs/research/git-worktrees/` should cover:

### Section 1 — What's the Superhuman-style pattern?

- Cite the actual pattern from their engineering blog or conference talk if findable.
- If no canonical source exists, generalize from community practice and note that the reference is informal.
- Describe it concretely enough that someone unfamiliar can tell what's being proposed.

### Section 2 — Value analysis (the load-bearing section)

For each of the following, rate whether worktrees add meaningful value in *this project's* flow:

- **Parallel agent pipelines** — can two `/kiln:kiln-build-prd` runs proceed simultaneously without interfering? Does `.wheel/` state survive parallel workflows in separate worktrees? (This is the biggest potential win if it works.)
- **Context switching** — is `git worktree add` + `cd` meaningfully faster than `git stash` + `git checkout` for the typical interrupt-driven dev session?
- **Abandoned-attempt isolation** — would worktrees let the research-first track keep failed attempts around in a separate tree without polluting the primary checkout? (Ties directly to `2026-04-24-research-first-feature-track`.)
- **Cost/benefit vs complexity** — worktrees add a mental model overhead (multiple working directories, figuring out which one's "active", cleanup discipline). Is the value delta large enough to justify the extra concept?

### Section 3 — Where it fits in our flow

Explicitly map worktree usage to each existing flow:

- `/kiln:kiln-init` — any change? (probably not)
- `/kiln:kiln-build-prd` — spawn the pipeline in a new worktree per PRD?
- `/kiln:kiln-fix` — isolated worktree per bug fix?
- Research-first track (`2026-04-24-research-first-feature-track`) — worktree per feasibility attempt, abandoned cleanly with the branch?
- `/kiln:kiln-report-issue`, `/kiln:kiln-feedback`, `/kiln:kiln-roadmap` — these are read-heavy against `.kiln/` state; does running them from a worktree produce different results than the main checkout?
- Agent teams — does the wheel engine's per-agent state survive when agents work in different worktrees of the same repo?

### Section 4 — Known failure modes to probe

- **Shared state in `.wheel/` and `.kiln/`** — these directories are repo-local but NOT branch-local. Two worktrees on different branches share `.wheel/state_*.json`. Does that cause collisions?
- **`.shelf-config` and Obsidian mirror paths** — paths are repo-slug-keyed, not branch-keyed. Two worktrees writing to the same Obsidian path will race.
- **Hook path resolution** — hooks read from CWD. Running a hook from a worktree means `plugin-*/scripts/` lives in the main checkout, not the worktree. Does `${CLAUDE_PLUGIN_ROOT}` still resolve correctly?
- **Version counter / `VERSION` file** — auto-incremented on every edit. Two worktrees editing in parallel would race on the same file (currently `.version.lock` guards this in a single checkout; does that extend?).

### Section 5 — Go/no-go recommendation

Based on Sections 2-4, one of:
- **Go** — worktrees add meaningful value; capture a follow-on PRD scoping integration work (which hooks/scripts need changes, which state files need per-worktree isolation).
- **Defer** — value is real but the integration cost is higher than the current pain; revisit when pain grows (e.g., when we actually need to run parallel pipelines, not just imagine doing so).
- **No** — neutral or negative for this project; current single-checkout + branch-switching flow is sufficient.

## Time-box

1 session. Value analysis + quick scan of failure-mode surfaces + go/no-go. Not an exhaustive integration plan — that's a follow-on PRD if the verdict is Go.

## Audience for the conclusion

- **Primary**: you, deciding whether to invest in a worktree-adoption PRD.
- **Secondary**: future-you and future agents reading the research doc to understand "why did we / didn't we adopt worktrees." The doc should explain the reasoning grounded in concrete touchpoints (specific hooks, specific state files, specific Obsidian paths) — not just land on a verdict without showing the work.

## Cheapest directional answer first

Before the full investigation: answer one question first — **would this actually make anything in the current dev cycle faster or more parallel?** If the honest answer is "probably not — we're a solo dev with a single in-flight PRD at a time and no need to run parallel pipelines," that's an 80% signal that the full research isn't worth the session. Only invest in Sections 2-4 if the honest answer is "yes, here's a concrete scenario where worktrees would help today."

## Dependencies

- No blocking dependencies.
- **Compositional with `2026-04-24-research-first-feature-track`** — worktrees and research-first track are natural partners if the verdict is Go (each research-first attempt lives in its own worktree, abandoned attempts stay isolated without polluting the main checkout).
- **Compositional with `2026-04-24-team-readiness-minimum-diff`** — worktrees are adjacent to the "what breaks under git's normal concurrent-editing affordances" audit; if worktrees prove valuable for solo dev, they're even more valuable for any future multi-user scenario.
