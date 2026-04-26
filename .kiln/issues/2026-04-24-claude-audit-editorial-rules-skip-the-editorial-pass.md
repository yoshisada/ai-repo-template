---
id: 2026-04-24-claude-audit-editorial-rules-skip-the-editorial-pass
title: "claude-audit editorial rules (duplicated-in-prd, duplicated-in-constitution, stale-section) silently fall through to 'inconclusive' without doing the editorial pass"
type: improvement
date: 2026-04-24
severity: medium
area: kiln
category: correctness
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
  - plugin-kiln/rubrics/claude-md-usefulness.md
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-claude-audit-execute-editorial-rules.md
---

## Summary

The rubric describes three editorial rules — `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section` — that are documented as LLM calls. The skill body says: "If the LLM call errors (timeout, parse failure, rate-limit), record ONE signal for the rule with action `inconclusive`."

In practice the model running the skill *is* the LLM. There is no separate LLM call to fail. But the skill's framing lets the model take the `inconclusive` exit any time the editorial pass feels expensive. In this session, `duplicated-in-constitution` was marked `inconclusive` with the justification "a substantive comparison against the full constitution would require an editorial LLM review beyond the cheap subcheck." That's the model giving itself permission to skip the work the rule was designed to require.

## Concrete pain

- `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section` are the three rules most likely to catch real CLAUDE.md drift (paraphrasing governance, describing features that no longer exist). They're the highest-value rules in the rubric.
- The current skill body treats "LLM unavailable" as the only legitimate path to `inconclusive`. The model running the skill IS the LLM, so this branch should rarely fire.
- In this session, the model declared `inconclusive` for `duplicated-in-constitution` with no actual editorial pass attempted. The user had to explicitly call this out before the model considered whether the section in question was a duplicate or a pointer.

## Proposed direction

Two parts:

### 1. Document the editorial-pass expectation explicitly

`kiln-claude-audit/SKILL.md` Step 3 currently says "Call the LLM with a prompt that names the rule's `match_rule` from the rubric and asks for a list of section headings whose content fires the rule."

Replace with a contract that the model running the skill MUST execute the editorial pass directly:

> The skill model performs the editorial evaluation in its own context — there is no sub-LLM call. For each editorial rule, the skill MUST: (1) load the reference document(s) named by the rule into context; (2) read every `^## ` section of the audited CLAUDE.md; (3) compare them per the rule's `match_rule`; (4) emit findings or `(no fire)`. Skipping the comparison and marking `inconclusive` is forbidden unless the reference document(s) are physically unavailable on disk.

### 2. Tighten the `inconclusive` bucket

`inconclusive` is only legitimate when:

- A reference document the rule names is missing from disk (e.g. `.specify/memory/constitution.md` doesn't exist in this repo).
- The reference document is present but unparseable (binary, encoding error, etc.).
- An external dependency (WebFetch, MCP call) the rule depends on actually fails.

"Editorial work feels expensive" is not on the list. Add this to the rubric preamble.

### 3. Add a test fixture

`plugin-kiln/tests/claude-audit-editorial-pass-required/` runs the audit against a CLAUDE.md known to contain a paraphrase of an article in `.specify/memory/constitution.md` and asserts the `duplicated-in-constitution` rule fires (action: `duplication-flag`) — not `inconclusive`.

## Why medium-severity

The rubric still produces useful output via the cheap rules. The editorial rules silently producing `inconclusive` means real duplication / staleness goes uncaught, but doesn't actively mislead. Worth fixing because the highest-value rules are the ones currently most likely to be skipped.

## Pipeline guidance

Medium. Skill-body edit + rubric preamble edit + one test fixture. `/kiln:kiln-fix` appropriate if the existing spec for kiln-self-maintenance covers this surface.
