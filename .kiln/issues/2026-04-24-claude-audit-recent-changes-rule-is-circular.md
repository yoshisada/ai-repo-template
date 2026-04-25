---
id: 2026-04-24-claude-audit-recent-changes-rule-is-circular
title: "claude-audit recent-changes-overflow rule is self-defeating — the section is load-bearing because the rule cites it, and the section design is itself an anti-pattern"
type: improvement
date: 2026-04-24
status: open
severity: medium
area: kiln
category: design
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/rubrics/claude-md-usefulness.md
  - plugin-kiln/rubrics/claude-md-best-practices.md
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
  - plugin-kiln/skills/kiln-doctor/SKILL.md
---

## Summary

Two problems compose into one bug:

1. **Circular load-bearing protection.** The `## Recent Changes` section is detected as load-bearing because two skills cite it by name: `kiln-claude-audit/SKILL.md` line 148 ("count bullets under `## Recent Changes`") and `kiln-doctor/SKILL.md` line 198 ("Count bullets under `## Recent Changes`"). The `load-bearing-section` rule then protects the section from removal — meaning the section exists primarily because the rule that targets it exists.

2. **The section design is itself an anti-pattern.** Anthropic's CLAUDE.md guidance (cached at `plugin-kiln/rubrics/claude-md-best-practices.md`) lists "Information that changes frequently" in the ❌ Exclude column. A manually-curated changelog tail in CLAUDE.md is exactly that. Git log + `.kiln/roadmap/items/` + `docs/features/` already contain this information; CLAUDE.md replicating it is drift-by-design.

The rubric currently has `recent-changes-overflow` (count > N → archive) which assumes the section exists and is appropriately maintained. There is no rule for "this section's existence is the bug, not its overflow."

## Concrete pain

- Removing `## Recent Changes` (which the audit *should* recommend per Anthropic's guidance) silently deactivates two cheap rules without warning. Not a bug — they go inert gracefully — but the rubric and skill bodies still describe them as if they fire.
- `kiln-claude-audit/SKILL.md` line 148 and `kiln-doctor/SKILL.md` line 198 still say "Count bullets under `## Recent Changes`. If count > threshold, fire with action `archive-candidate`." Neither says "if section is absent, treat as no drift."
- The `load-bearing-section` rule's purpose is to protect sections cited from skills/agents/hooks/workflows. It correctly fires for `## Architecture`, `## Security`, `## Active Technologies`, `## Recent Changes`. But "cited by the rule that targets you" is a different category from "cited as load-bearing reference content" — the protection mechanism doesn't distinguish.

## Proposed direction

Three parts:

### 1. Add a `recent-changes-anti-pattern` rule

```yaml
rule_id: recent-changes-anti-pattern
signal_type: substance
cost: cheap
match_rule: presence of "## Recent Changes" heading
action: removal-candidate
rationale: Manually-curated changelog tail in CLAUDE.md is "frequently-changing information" per Anthropic guidance — duplicates git log / .kiln/roadmap/ and drifts faster than it adds value.
cached: false
```

Proposed diff: replace the section with a one-paragraph "## Looking up recent changes" block that points at `git log`, `.kiln/roadmap/phases/08-in-flight.md`, `ls docs/features/`, and `/kiln:kiln-next`. (This is the pattern applied to the kiln source repo's CLAUDE.md in fix `2026-04-24-claude-md-and-scaffold-substance-rewrite`.)

### 2. Make `recent-changes-overflow` graceful when section is absent

Update `kiln-claude-audit/SKILL.md` line 148 and `kiln-doctor/SKILL.md` line 198:

> If `## Recent Changes` section is absent, the rule emits no signal (treat as no drift). If `recent-changes-anti-pattern` has fired, demote `recent-changes-overflow` to `keep` for the same reason `load-bearing-section` demotes others.

### 3. Distinguish "cited as content" from "cited as rule target" in load-bearing detection

The `load-bearing-section` rule should NOT protect a section solely because a rule definition cites it. Reword its match: a section is load-bearing if cited from skill/agent/hook/workflow **prose** (instructions, descriptions, error messages). It is NOT load-bearing if cited only inside a rule's `match_rule:` field, since that's tautological.

The current rubric implements this implicitly via the false-positive shape ("a plugin that greps the literal string `CLAUDE.md` ... does NOT make any section load-bearing"). Extend that to: "a rule whose `match_rule:` cites a section header does NOT make that section load-bearing for protection purposes — the rule is the only consumer, and the rule itself can be deprecated."

Same applies to `## Active Technologies` (cited by `active-technologies-overflow` and the rubric preamble — same circularity).

## Why medium-severity

The current state ships a working audit. The circularity makes the rubric less honest about what it's actually protecting, and makes deprecating either section harder than it should be. Worth fixing in the same PRD as `claude-audit-rubric-missing-substance-rules` (high-severity sibling) since both are about evolving the rubric.

## Pipeline guidance

Medium. Rubric edit + two skill-body edits + one new rule entry + a test fixture asserting the new rule fires when `## Recent Changes` is present. Likely fits inside the same PRD as the substance-rules issue.
