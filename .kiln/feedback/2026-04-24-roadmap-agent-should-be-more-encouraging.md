---
id: 2026-04-24-roadmap-agent-should-be-more-encouraging
title: Roadmap interview should coach with insight, not just interrogate
type: feedback
date: 2026-04-24
status: prd-created
severity: medium
area: ergonomics
repo: null
prd: docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md
roadmap_item: .kiln/roadmap/items/2026-04-24-roadmap-coaching-with-insight.md
---

roadmap agent should be more incuraging and insightful as to how this could help or how it could be architected to best help.  right now it feels dull

## Interview

### What does "done" look like for this feedback? Describe the observable outcome.

I want the roadmap to tell me 'why' it's a good idea or bad idea and how it helps solve our ending mission. I want it to suggest its best choices for each question. Should have an accept-all command, or "tweak xyz then accept all".

### Who triggers the change, and when? (ad-hoc skill, hook, background agent, part of an existing skill, human maintainer decision…)

Part of the existing /kiln:kiln-roadmap skill — triggered whenever a user captures an item; no separate trigger needed.

### What's the scope? Just this repo, consumer repos too, or other plugins as well?

This repo (plugin-kiln source) — change ships to every consumer that installs/updates the kiln plugin. Other plugins (shelf, wheel, clay) unaffected unless they later adopt the same coaching pattern.

### Which existing friction point does this resolve, and how will you know it's gone?

Friction: the interview feels like a checklist — users disengage, give thin answers, or hit skip mid-way. Resolved when (a) skip-rate drops, (b) item bodies show richer reasoning instead of one-liners, and (c) the user finishes feeling oriented — knowing why the item matters and what it connects to in the existing roadmap. Also a general UX improvement — capture should feel collaborative, not like form-filling.

### Is there a paired tactical backlog entry in .kiln/issues/ that this feedback pairs with? (path, or "none")

none — this is a fresh strategic note about the roadmap-skill experience, not a tactical bug already filed.
