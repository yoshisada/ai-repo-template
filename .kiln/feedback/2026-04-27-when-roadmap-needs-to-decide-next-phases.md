---
id: 2026-04-27-when-roadmap-needs-to-decide-next-phases
title: kiln-roadmap should rank next-phase candidates by capture surface — issues > feedback > queued > brainstorming
type: feedback
date: 2026-04-27
severity: medium
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-27-roadmap-priority-ranked-next-phase.md
---

when roadmap needs to decide next phases from prd, it should take into account issues first, feedback next, then queued items, then brainstormed items.

## Interview

### What does "done" look like for this feedback? Describe the observable outcome.

When `/kiln:kiln-roadmap` proposes what to graduate into the next active phase, it walks the four capture surfaces in a fixed priority order: `.kiln/issues/` first, `.kiln/feedback/` second, `phase: 90-queued` items third, brainstorming items fourth. The suggestion output reflects that ranking — the user sees issues at the top of the candidate list and brainstorming at the bottom.

### Who triggers the change, and when? (ad-hoc skill, hook, background agent, part of an existing skill, human maintainer decision…)

User-triggered via `/kiln:kiln-roadmap` (likely a new sub-verb like `--propose-next` or `--plan-phase`). Not a hook, not a background agent. Fires during phase-planning when the user asks "what should the next phase contain?"

### What's the scope? Just this repo, consumer repos too, or other plugins as well?

This repo for the skill change; consumer repos inherit it via the kiln plugin install. Other plugins (clay/trim/wheel/shelf) unaffected.

### What structural boundary or plugin shape does this change?

Codifies a deterministic priority rule inside `/kiln:kiln-roadmap`'s contract — which capture surface "wins" when ranking next-phase candidates. Touches the skill body (new ordering block) and likely a new sub-verb. No on-disk state changes; only changes how the skill reads existing surfaces. Note: requires the "brainstorming" state from the related issue (`2026-04-27-kiln-roadmap-unaware-of-queued-brainstorming-states.md`) to be defined first, or this rule has nothing to point at for tier 4.

### What does the rollout look like — one PR, staged, or a migration?

One PR. Add the priority rule + the verb that exercises it. No migration because no on-disk state changes. Sequence after (or bundled with) the queued/brainstorming-states issue so tier 4 has a real referent.
