---
id: 2026-04-25-vision-update-needs-simple-params-cli
title: "Vision updates need a simple-params CLI — current /kiln:kiln-roadmap --vision flow is too heavyweight for one-line additions"
type: feedback
date: 2026-04-25
severity: medium
area: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - .kiln/vision.md
  - plugin-kiln/skills/kiln-roadmap/SKILL.md
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-25-vision-simple-params-cli.md
---

The vision file (`.kiln/vision.md`) holds the load-bearing product principles — guiding constraints, what we're building, what's out of scope, success signals. It needs to be updated regularly as architectural insights surface mid-session (today's example: the "wheel is plugin-agnostic infrastructure" principle that emerged from the FR-A1 reversal conversation).

Currently the only canonical update path is `/kiln:kiln-roadmap --vision`, which runs an interactive coached flow per the kiln-roadmap skill spec — orientation block, evidence-grounded draft, per-section diff prompts with accept/reject/step-through affordances. That flow is well-designed for first-run drafting or major re-anchoring, but it's wildly heavyweight for the common case: *"add this one constraint to the Guiding constraints section."*

The friction this creates: when a useful principle surfaces mid-session, the choice is:
- **(a)** Run the full coached interview to add a single bullet — minutes of UI work for one line of content
- **(b)** Edit `.kiln/vision.md` directly — fast but bypasses any guardrails (frontmatter `last_updated:` bump, validation, mirror dispatch)
- **(c)** Defer to "later, I'll do it properly" — and watch the principle decay before it gets captured

Today during the FR-A1 reversal conversation I went with (b) — direct edit. Worked, but the precedent is bad: every subsequent vision-evolving insight will route around the canonical flow.

## Proposed direction

Add a non-interactive simple-params mode to `/kiln:kiln-roadmap --vision` (or a sibling skill `/kiln:kiln-vision`) that takes section-targeted parameters:

```
/kiln:kiln-roadmap --vision --add-constraint "Wheel is plugin-agnostic infrastructure — ..."
/kiln:kiln-roadmap --vision --add-non-goal "Not a multi-tenant SaaS"
/kiln:kiln-roadmap --vision --add-success-signal "Build-prd produces a shippable PR with no human intervention 80% of the time"
/kiln:kiln-roadmap --vision --update-what-we-are-building "<full new para>"
```

Each form does the minimum needed:
1. Read the existing `.kiln/vision.md`
2. Append (or replace, for the `--update-*` form) the targeted section
3. Bump `last_updated:` to today's date
4. Write atomically (temp + mv)
5. Optionally dispatch shelf mirror

No interview, no diff prompts, no orientation block. Trust the user typed the right thing.

The full coached flow (`/kiln:kiln-roadmap --vision` with no section flag) stays as the heavyweight option for major re-anchoring, first-run drafting, or when the user explicitly wants the AI to surface drift suggestions.

## Why this matters

Vision drift is invisible. When the canonical update path is heavyweight, mid-session insights either bypass it (creating undocumented direct edits) or get lost. Either way, the vision file falls out of sync with actual product thinking. A simple-params CLI is the difference between "I'll capture this principle now while it's fresh" and "I'll write it down properly later" — and "later" rarely happens.

## Concrete pain example (this session)

The "wheel is plugin-agnostic infrastructure" principle emerged from a 5-message exchange about why the FR-A1 reversal mattered. It's a load-bearing test for future architectural decisions ("does this require wheel to know about another plugin's contents?"). I added it as a Guiding constraint via direct file edit — bypassing whatever validation `/kiln:kiln-roadmap --vision` would have applied. A simple `--add-constraint <text>` would have given me the same speed PLUS the proper update path.

## Adjacent

This is the same shape of friction as `/kiln:kiln-feedback` itself — the early friction-capture skills had heavyweight interviews; the lightweight one-liner forms came later as opt-outs. Same pattern would apply here: keep the rich interview as the default for first-run / major edits, add simple-params for the common case.
