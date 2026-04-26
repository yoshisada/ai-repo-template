---
id: 2026-04-24-claude-audit-fr013-citation-produces-decoration
title: "claude-audit FR-013 project-context citation requirement encourages vacuous decoration, not real grounding"
type: improvement
date: 2026-04-24
severity: medium
area: kiln
category: design
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
  - specs/coach-driven-capture-ergonomics/contracts/interfaces.md
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-claude-audit-grounded-citations.md
---

## Summary

The skill's FR-013 requirement says: "every preview MUST render the `## Project Context` block and cite at least one signal from it in findings. An audit that fails to ground itself in project context is a regression."

The intent is to ground findings in repo state. In practice, the model running the skill satisfies the rule by emitting decorative citations like:

> Project-context signals cited in findings: active phase `08-in-flight` (informs the length-density finding via accumulated-work context), plugin list `clay,kiln,shelf,trim,wheel` (informs the excluded-category-drift finding — five plugins is a structural reason Available Commands trends long), shipped PRD count `46` (informs the length-density finding).

None of those citations were actually load-bearing for the finding — they were post-hoc justifications added to satisfy the FR. The length-density finding fired because `wc -l CLAUDE.md = 252`. The fact that there are 5 plugins or 46 PRDs is an interesting *correlation* but not a *cause*. The FR forces the audit to invent these correlations.

## Concrete pain

- The `## Project Context` block became a checkbox: print the phase / plugins / PRD count. Done.
- The "signals cited in findings" line in Notes is generated to satisfy the assertion, not because the citations actually drove the findings.
- The substance findings filed *late* in this session (after the user explicitly demanded a "full fledged audit") DID actually ground in project context — they cited the vision file's load-bearing concepts as the missing referent. But the original rubric findings did not, and the FR didn't catch that.
- Worse: the FR says "an audit that fails to ground itself in project context is a regression." Decoration *passes* this assertion, so the FR does not catch the failure mode it claims to.

## Proposed direction

Two changes:

### 1. Require primary justification, not secondary correlation

Tighten the FR: every cited project-context signal MUST be the *primary justification* for at least one finding. Primary justification = removing the signal from the audit's reasoning would change the finding's verdict (would fail to fire / fire differently / change action).

Example of primary justification:
- `substance/missing-thesis` cites `vision present (.kiln/vision.md articulates "the loop is the product"), audited file does not summarize the thesis` — the audit cannot fire this finding without the vision content. Removing vision from context = no finding.

Example of decoration:
- `external/length-density` cites `shipped PRD count 46 informs the length-density finding` — the audit fires from `wc -l = 252`, not from PRD count. Removing PRD count from context = same finding.

### 2. Strengthen the assertion

Replace "An audit that fails to ground itself in project context is a regression" with: "Every audit MUST contain at least one finding whose `match_rule` reads from `CTX_JSON` (vision body, roadmap items, plugin list, README, CLAUDE.md prior state). Length-only / freshness-only audits are not grounded — they evaluate the file in isolation. If no project-context-driven finding fires, the audit MUST emit a `(no project-context signals fired)` row in the Signal Summary so the maintainer sees the gap."

### 3. Audit the audits

Add `plugin-kiln/tests/claude-audit-grounded-finding-required/` — a test fixture where CLAUDE.md is structurally clean (passes all rubric rules) BUT diverges from `.kiln/vision.md` content. Asserts the audit emits at least one substance finding that cites vision content as primary justification.

## Why medium-severity

The FR is well-intentioned but currently produces theater. Decoration in Notes makes the audit *look* grounded while every actual finding fires from rubric rules that don't read project context. Tightening this is what makes substance-driven auditing actually work — pairs naturally with the high-severity `claude-audit-rubric-missing-substance-rules` issue.

## Pipeline guidance

Medium. Skill body + spec FR rewording + new test fixture. The substance-rules PRD likely covers this in its design — file these together.
