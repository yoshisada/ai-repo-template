---
id: 2026-04-24-claude-audit-rubric-missing-substance-rules
title: "claude-audit rubric has no rules for 'does this file teach what the project is?' — substance findings have to be invented ad-hoc"
type: improvement
date: 2026-04-24
severity: high
area: kiln
category: design
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/rubrics/claude-md-usefulness.md
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
  - plugin-kiln/rubrics/claude-md-best-practices.md
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-claude-audit-substance-rules.md
---

## Summary

The `claude-md-usefulness.md` rubric covers length / freshness / load-bearing / duplicated-in-PRD / duplicated-in-constitution / stale-section. None of those rules ask the most important question: **does this file teach a new reader what the project is and how the system is supposed to work?**

When this skill ran against the kiln source repo's CLAUDE.md, the rubric produced clean rule firings (compress long bullets, fix a deprecated command reference, add a Testing block) — but missed that the file described mechanics ("spec-first development workflow with 4-gate enforcement") and never named the load-bearing concepts the vision file articulates: the five-plugin suite, "the loop is the product," precedent-driven autonomy, the senior-engineer-merge bar, propose-don't-apply universality. The audit produced a polished-looking report that left every load-bearing concept of the project undocumented in CLAUDE.md.

The user had to challenge the audit three separate times ("did you add anything about vision?", "did we say anything about the loop?", "did you read anything about the project?") before the substance findings emerged. Each one had to be filed under an ad-hoc `substance/*` rule_id because there was no canonical rule covering it.

## Concrete pain

- The skill loads `.kiln/vision.md` into `CTX_JSON` (FR-013 path) and then cites only line counts and section names from it. It never *evaluates the audited file against the vision's claims*.
- Substance findings filed in this run had to invent rule_ids: `substance/missing-thesis`, `substance/missing-loop`, `substance/missing-suite-context`, `substance/scaffold-undertaught`. None exist in the rubric.
- The `external/included-category-gap` finding got close but is framed as "missing Testing block" — it doesn't generalize to "missing thesis," "missing loop," or "missing five-plugin suite context."
- A consumer-installed CLAUDE.md (the scaffold) that teaches no thesis, no loop, and no invariants passes the rubric trivially because the rubric doesn't have a rule for "consumer learns nothing."

## Proposed direction

Add four canonical rules to `claude-md-usefulness.md`, each with its own `rule_id`, `signal_type: substance`, `cost: editorial`:

1. **`missing-thesis`** — file describes mechanics but never names the project's stated purpose / vision pillars. Match by reading `.kiln/vision.md` (when present) and verifying ≥1 vision pillar is named in the audited file's opener.
2. **`missing-loop`** — for projects whose vision claims a process loop (capture → distill → ship → improve, or analogous), the file must draw the loop. Match by reading vision + roadmap-phase status; if the project has shipped a loop and the file doesn't draw it, fire.
3. **`missing-architectural-context`** — Architecture section describes one component when the project comprises multiple cooperating components (multi-plugin, multi-service, multi-repo). Match: count distinct top-level package roots / plugin directories; if >1 and the section describes only one, fire.
4. **`scaffold-undertaught`** — applies to scaffold/template CLAUDE.md files. Verify the scaffold communicates the same load-bearing concepts (thesis, loop, invariants) that the source repo's CLAUDE.md does. Match by diffing the conceptual coverage between the two.

These rules should rank ABOVE the rubric's length / freshness rules in the audit's `## Signal Summary` and `## Notes` (recommended apply order).

## Why high-severity

The point of the skill is to catch CLAUDE.md drift. "Drift" in the rubric currently means length and staleness; the rubric is silent on the most expensive form of drift, which is **omitting the project's load-bearing concepts**. Every audit run that focuses on length while CLAUDE.md fails to teach the project's thesis is an audit that confirms the wrong thing.

## Pipeline guidance

High severity. Worth a full PRD — these are rule additions to a published rubric, schema-shaped frontmatter, plus updates to `kiln-claude-audit/SKILL.md` Step 3 to evaluate them. Touches `plugin-kiln/rubrics/claude-md-usefulness.md`, the skill body, and likely a follow-on test fixture under `plugin-kiln/tests/claude-audit-substance/`.
