---
id: 2026-04-23-claude-md-should-be-refreshed-audited
title: CLAUDE.md needs a refresh/audit mechanism — source and consumer template
type: feedback
date: 2026-04-23
status: prd-created
prd: docs/features/2026-04-23-kiln-self-maintenance/PRD.md
severity: high
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
files:
  - CLAUDE.md
  - plugin-kiln/scaffold/CLAUDE.md
---

CLAUDE.md file should have a way to be refreshed/audited to make sure it's actually useful.

## Why this matters

CLAUDE.md is loaded into every Claude Code session in this repo AND in every consumer repo scaffolded by `plugin-kiln/bin/init.mjs`. Every line costs context-window tokens forever, across every session the plugin is installed in. Bloat here is a multiplicative, permanent tax.

This isn't tactical polish — it's a structural gap in how the kiln product maintains its own context file over time.

## What the audit mechanism should do

**Trigger surfaces (two paths)**:
1. Ad-hoc via a dedicated command invoked by the maintainer (e.g., `/kiln:kiln-audit-claude` or a subcommand under `/kiln:kiln-doctor`)
2. Part of `/kiln:kiln-doctor` — integrated into the existing structural-validation sweep

**Definition of "useful"**:
- Research + store the rubric. The audit shouldn't rely on a hardcoded notion of what "useful" means — it should have a documented, versioned rubric that can evolve. The rubric lives somewhere like `plugin-kiln/rubrics/claude-md-usefulness.md` (or equivalent).
- The rubric should cover at least: load-bearing signals (grep references from skills/agents/hooks/workflows — if a skill body says "read CLAUDE.md section X", that section stays); editorial signals (LLM-judgment for stale/duplicated content against docs/PRD.md and constitution.md); freshness heuristics (migration notices that are >3 months old are candidates for removal; "Recent Changes" entries beyond the last N are candidates for archival).
- Research phase is an explicit upfront task — before the skill is built, we spend the time to understand what "useful CLAUDE.md content" actually means for this plugin.

**Outcome shape**:
- The audit PROPOSES edits, does NOT apply them. Output is a `git diff`-style preview that the maintainer reviews before committing.
- Diff lands in `.kiln/logs/claude-md-audit-<date>.md` (or similar — per the existing log pattern).
- After review, the maintainer applies the diff manually (or via a follow-up "accept" command — design decision for the PRD phase).

**Scope — both source and consumer template**:
- Primary: the source repo's `CLAUDE.md` at the repo root.
- Secondary, but equally important: the consumer-repo template at `plugin-kiln/scaffold/CLAUDE.md`. Per the maintainer: "the consumer template should probably be rewritten as it's not exactly relevant anymore." The template has drifted. The audit feature should either (a) propose a rewritten consumer template as a one-time cleanup, or (b) include the consumer template in every audit run going forward.

## Follow-on structural concerns (not in scope for the initial PRD but worth flagging)

- **Governance to prevent future bloat**: maybe a top-of-file policy comment ("every section in this file must be referenced by a skill/agent/hook, or it's a candidate for removal on next audit") to slow accumulation.
- **Related backlog item**: `.kiln/issues/2026-04-23-claude-md-audit-and-prune.md` is the tactical twin of this feedback — a specific ask for the audit+prune pass. This feedback is the strategic "we need the mechanism" layer underneath.

## Suggested next step

Run `/kiln:kiln-distill` to bundle this feedback + the tactical backlog item into a feature PRD. Feedback should lead the narrative (the strategic "kiln owns CLAUDE.md maintenance" framing); the tactical issue forms the first audit pass. PRD can also scope the consumer-template rewrite explicitly.
