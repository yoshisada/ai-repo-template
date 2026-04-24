---
id: 2026-04-24-kiln-vision-self-exploring-and-self-updating
title: /kiln:kiln-roadmap --vision should self-explore the repo first, then ask clarifying questions, and self-update as the project evolves
type: improvement
date: 2026-04-24
status: prd-created
severity: medium
area: kiln
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-roadmap
  - .kiln/vision.md
  - .kiln/roadmap/items
  - docs/features
prd: docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md
---

## Summary

The current `/kiln:kiln-roadmap --vision` flow shows the user a blank vision template and asks three open-ended questions ("What's changed?", "What's still true?", "What's newly out-of-scope?"). On first run or after major project evolution, that's the wrong starting point — the user is being asked to cold-start a vision document when the repo already contains rich evidence of what's being built, why, and where it's going.

The skill should **self-explore first, draft a candidate vision from what it finds, then come back to the user for clarifications on the gaps**. And on subsequent invocations, it should re-read the project state and propose *diffs* to the vision rather than asking the user to rewrite from scratch.

## What "self-exploring" means in this repo

The skill can derive a plausible first-draft vision from:

- `docs/features/*/PRD.md` — the PRDs describe every shipped or in-flight product capability.
- `.kiln/roadmap/items/` — typed roadmap items (features, constraints, critiques, non-goals) are direct inputs to the "what we are / aren't building" and "guiding constraints" sections.
- `.kiln/roadmap/phases/*.md` — phase files show what's complete vs in-progress vs planned, which shapes "how we'll know we're winning."
- `README.md` and `CLAUDE.md` — top-level framing of the product's mission and scope.
- `package.json` / plugin manifest files — lists of plugins (kiln, shelf, clay, trim, wheel) that signal the product surface area.
- Open critiques (items with `kind: critique`) — direct sources for "what it is not" and "guiding constraints."

A self-exploring vision pass would read these, draft each of the four vision sections with cited evidence, THEN ask the user:

1. Anything in the draft that's wrong?
2. Anything missing that you'd include?
3. Anything you want to explicitly rule out (non-goals) that the draft doesn't mention?

That's a much higher signal interview than the current blank-slate questions.

## What "self-updating as the project evolves" means

When `/kiln:kiln-roadmap --vision` runs again after new features have shipped:

- The skill re-reads the same sources.
- It diffs what the repo says now vs what `.kiln/vision.md` currently claims.
- It surfaces **specific proposed edits** ("PRD for X shipped last month — should 'What we are building' mention X as a core capability? [yes/no/rephrase]"), not blank-slate questions.
- The user approves / rejects individual edits, not a wholesale rewrite.

This keeps the vision document a living artifact that tracks reality, rather than a one-off stub that rots.

## Why this matters

Vision documents are load-bearing for `/kiln:kiln-distill` and `/kiln:kiln-build-prd` — they set the frame that downstream PRD narratives are expected to ladder up to. A stub vision means those skills fall back on implicit framing that drifts from the user's actual intent. Making the vision flow self-exploring turns it from "homework the user owes the skill" into "a draft the user edits."

## Proposed acceptance

- On first invocation with a fresh `.kiln/vision.md`, the skill reads PRDs + roadmap items + phases + README/CLAUDE.md, drafts all four vision sections with concrete content, and presents the draft for review.
- On subsequent invocations, the skill diffs current-repo-state against `.kiln/vision.md` and proposes specific line-level edits tied to evidence ("PRD X shipped → propose adding X to 'What we are building'").
- The user can accept all, reject all, or step through edits individually.
- The `last_updated:` frontmatter is bumped on any accepted edit.
- Fallback: if the repo has insufficient signal (e.g., brand-new repo with no PRDs or items), the skill falls back to the current blank-slate question path.

## Pipeline guidance

Medium severity — this is a real UX improvement with a cascading effect on distill/PRD quality, but not blocking. Full pipeline is appropriate (specify → plan → tasks → implement → audit) but does not strictly require a retrospective; the fix is scoped and the test surface (vision document freshness) is straightforward.
