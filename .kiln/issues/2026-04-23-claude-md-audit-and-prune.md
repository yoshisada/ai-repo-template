---
title: Audit and prune CLAUDE.md for kiln — distinguish load-bearing content from accumulated bloat
type: improvement
severity: medium
category: documentation
status: prd-created
prd: docs/features/2026-04-23-kiln-self-maintenance/PRD.md
repo: https://github.com/yoshisada/ai-repo-template
files:
  - CLAUDE.md
date: 2026-04-23
---

# Audit and prune CLAUDE.md for kiln — distinguish load-bearing content from accumulated bloat

## Description

We need a way to audit and upgrade `CLAUDE.md` for kiln and its projects. The file has grown through many pipelines and it's no longer clear which sections are load-bearing (agents and skills depend on them) vs. which sections are stale, redundant, or accumulated bloat.

CLAUDE.md is loaded into every Claude Code session in this repo, so every line costs context-window tokens forever. Every kiln pipeline also runs in consumer repos with their own CLAUDE.md — if the scaffolded template carries the same bloat, it multiplies across every project.

## What's missing

- A way to identify which sections of CLAUDE.md are actively referenced by skills, hooks, agents, or workflows (load-bearing) vs. which are narrative/historical/duplicated elsewhere (candidates for removal).
- A systematic audit that groups content by criticality: "must stay", "probably stale", "clear bloat".
- A pruning pass that removes the bloat without breaking skills that read specific sections or headers.
- A pattern for keeping CLAUDE.md lean over time — maybe a policy ("additions must cite what reads them") and/or a periodic audit cadence.

## Concrete signals of bloat in the current CLAUDE.md

(From a quick skim — worth revisiting during the audit itself)
- The "Migration Notice" about the `speckit-harness → kiln` rename is probably no longer load-bearing now that the rename is months old.
- The "Active Technologies" and "Recent Changes" sections at the bottom accumulate entries per feature branch — most are historical and not read by any agent.
- Some sections overlap with `docs/PRD.md` or `.specify/memory/constitution.md` — duplication means two sources of truth to maintain.
- The Architecture block is detailed; parts of it probably live better in per-plugin READMEs.

## Suggested approach

- **Phase 1 — Inventory**: grep plugin-*/skills/, plugin-*/agents/, plugin-*/hooks/, plugin-*/templates/ for every reference to CLAUDE.md (section headers, specific phrases, imports). That set defines "load-bearing".
- **Phase 2 — Classify**: for every section in CLAUDE.md, mark as "load-bearing", "narrative-worth-keeping", "stale", or "duplicated elsewhere".
- **Phase 3 — Prune + restructure**: remove/trim the stale + duplicated sections; move narrative bits that should live elsewhere (per-plugin READMEs, the constitution, docs/).
- **Phase 4 — Governance**: add a top-of-file comment or a short policy ("every section in this file must be referenced by a skill/agent/hook or it's a candidate for removal on next audit") to slow future bloat.

## Scope

- Primary target: the source repo's `CLAUDE.md`.
- Secondary target: the consumer-repo CLAUDE.md scaffolded by `plugin-kiln/bin/init.mjs` — same audit, same pruning, but template-shaped.
- Out of scope: per-plugin READMEs (those are a separate open backlog item).

## Related

- `.kiln/issues/2026-04-22-plugin-documentation.md` — adjacent but different (that one is per-plugin READMEs for consumers).
