---
id: 2026-04-24-kiln-vision-proactive-feature-suggestions
title: /kiln:kiln-roadmap --vision should proactively suggest system improvements and new features (long-term vision coaching)
type: improvement
date: 2026-04-24
status: open
severity: medium
area: kiln
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-roadmap
  - .kiln/vision.md
related:
  - 2026-04-24-kiln-vision-self-exploring-and-self-updating
---

## Summary

The `--vision` flow should be **more interactive and forward-looking**. Today (and under the in-flight `coach-driven-capture-ergonomics` PRD) the skill self-drafts the vision from repo evidence and proposes diffs that reconcile vision with current reality. That's good, but it's purely *backward-looking*.

The user wants the vision exercise to also include a **long-term-vision coaching layer**: after reconciling current state, the skill should actively **look at how the system can be improved and suggest new features / directions** for the user to consider — capturing accepted suggestions as `.kiln/roadmap/items/` on the way out.

## Relation to existing issue

- `2026-04-24-kiln-vision-self-exploring-and-self-updating` (status: `prd-created`, PRD: `docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md`) — covers self-drafting + diff-against-reality. **Backward-looking.**
- **This issue** — adds a forward-looking "what should we build next?" layer on top. Could be folded into the existing PRD if the human scoper prefers, or shipped as a follow-on once the self-drafting layer lands.

## Proposed behavior

After the current-state vision draft is accepted, the skill runs a second pass that:

1. **Gap analysis** — scans PRDs, roadmap items, phases, CLAUDE.md, and cross-references them against the drafted vision. Flags: "Your vision mentions X, but no PRD or roadmap item describes how we'd get there — want me to capture a research item?"
2. **Opportunity scan** — looks for patterns in recent PRDs and open critiques that suggest emergent product directions (e.g., "Three of the last five PRDs touched `plugin-shelf` reconciliation — is reconciliation ergonomics a theme worth naming as a phase or goal?").
3. **Adjacency suggestions** — proposes candidate features / capabilities that plausibly extend the current surface area (e.g., "You have `clay-create-repo` and `kiln-init`; there's no `clay-onboard-existing` — is that a gap?").
4. **Non-goal surfacing** — flags areas the user has previously declined to pursue (from `kind: non-goal` items) and asks whether any should be revisited now that context has changed.
5. **Capture hand-off** — for each accepted suggestion, offer to capture it as a typed roadmap item (via the same confirm-never-silent hand-off used elsewhere in `/kiln:kiln-roadmap`).

## Why this matters

Vision is currently something the user writes *down*, not something that actively **expands** the user's thinking. A proactive vision skill turns the command from "record what you know" into "discover what you didn't think to ask about" — which is the spirit of the broader autonomous-build thesis: the system flags when human judgement is needed AND brings fresh surface area for that judgement to act on.

## Proposed acceptance

- After the current-state vision draft (from the `coach-driven-capture-ergonomics` PRD) is accepted, the skill optionally runs a forward-looking pass (opt-in prompt: "Want me to suggest where the system could go next? [y/N]").
- The forward-looking pass generates ≤5 specific, evidence-cited suggestions grouped as: gap / opportunity / adjacency / non-goal-revisit.
- Each suggestion is individually acceptable; accepted ones spawn `.kiln/roadmap/items/` via the normal capture path (confirm-never-silent — not silent writes).
- Rejected or skipped suggestions are remembered (written to `.kiln/roadmap/items/<date>-<slug>-considered-and-declined.md` with `kind: non-goal` or a similar marker) so the next vision pass doesn't re-propose the same ideas.

## Pipeline guidance

Medium severity — extends `coach-driven-capture-ergonomics`. Either fold into that PRD as a Phase 7 or ship as a dedicated follow-on PRD after the backward-looking layer is verified. Not blocking.
