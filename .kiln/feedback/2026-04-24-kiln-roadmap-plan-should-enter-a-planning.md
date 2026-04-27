---
id: 2026-04-24-kiln-roadmap-plan-should-enter-a-planning
title: "/kiln:kiln-roadmap --plan should enter a planning mode to structure open items into logical phases and surface missing items"
type: feedback
date: 2026-04-24
severity: medium
area: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-roadmap-planning-mode.md
---

kiln-roadmap --plan should enter a planning phase to plan out the open items in roadmap so we can build in logical stages, also keeps in mind if something is missing.

## Interview

### What does "done" look like for this feedback? Describe the observable outcome.

A `/kiln:kiln-roadmap --plan` mode that, when invoked, reads all open items + current vision + existing phase state, proposes a set of theme clusters with suggested phase names and stopping criteria, lets the user accept/tweak/reject each cluster, and commits accepted clusters as new or extended phase files with items' `phase:` frontmatter updated in one atomic batch. Observable outcome: running `--plan` produces a reviewable "here's how the next 3-6 months of work wants to be structured" artifact in under a minute, and the user leaves the session with (a) one new or repopulated phase ready to start, (b) a shortlist of items explicitly parked as "not this phase," (c) optional flags on items that look like candidates for the research-first track. Also flags potential gaps — "your vision commits to X but no open items address it."

### Who triggers the change, and when? (ad-hoc skill, hook, background agent, part of an existing skill, human maintainer decision…)

Human-triggered via `/kiln:kiln-roadmap --plan`, on-demand. Natural cadence: at the end of a completed phase (right after `--phase complete`), or when the current phase feels stale, or when a big batch of captures has accumulated without structure. Not hook-driven, not scheduled — planning is a deliberate act requiring human judgement. `/kiln:kiln-next` MAY surface "you have N open unsorted items and the current phase has been in-progress for X sessions — consider running `--plan`" as a prompt, but never auto-runs.

### What's the scope? Just this repo, consumer repos too, or other plugins as well?

Scope: all consumer repos that install `@yoshisada/kiln`, not just this one. The `--plan` mode is part of the shipped `/kiln:kiln-roadmap` skill, so every consumer benefits. It composes with whatever the consumer has captured — their vision, their phases, their items. No cross-plugin surface area — this is pure `plugin-kiln` territory; no changes needed in shelf/clay/trim/wheel (though it reuses `plugin-kiln/scripts/context/` and the to-be-built `precedent-reader` if available).

### Which existing friction point does this resolve, and how will you know it's gone?

Friction: today phases emerge organically — you accumulate items, eventually realize several cluster, create a phase retroactively, move on. There's no deliberate moment to step back and say "what's the next 3 phases worth of work, and why?" The consequence is that phase granularity drifts (`01-foundations` is huge; `05-plugin-trim` is narrow), items sit in `unsorted` or `90-queued` without a forcing function to be reviewed, and the vision's strategic claims don't have an explicit mechanism to be translated into concrete next phases.

How I'll know it's gone: (a) new phases get created through `--plan` instead of ad-hoc, with explicit theme + stopping criterion in their frontmatter; (b) the count of items sitting in `unsorted` or `90-queued` for > N sessions trends toward zero; (c) I can point at a vision commitment and trace it forward to a planned phase and backward to items laddering up to it.

### Is there a paired tactical backlog entry in .kiln/issues/ that this feedback pairs with? (path, or "none")

No paired entry in `.kiln/issues/` — this is a pure strategic/ergonomics observation, not a bug or tactical friction. However, it has a closely related roadmap item: `.kiln/roadmap/items/2026-04-24-kiln-next-smarter-triage.md` — the smarter-triage sub-workflow and the `--plan` mode share triage logic (walk items, cluster by theme, surface what's ripe). When this feedback gets distilled into a PRD, that roadmap item should be considered alongside — either merged into the same PRD or explicitly scoped as a dependency. Path: `.kiln/roadmap/items/2026-04-24-kiln-next-smarter-triage.md` (roadmap, not issues).
