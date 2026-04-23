# Feature PRD: Kiln Self-Maintenance

**Date**: 2026-04-23
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (placeholder; product context inherited from `CLAUDE.md`)

## Background

Two strategic concerns surfaced in this cycle, both about the kiln plugin's ability to maintain its own internals rather than accumulating drift through accidental neglect:

1. **CLAUDE.md is load-bearing across every session and every consumer repo, but there is no mechanism inside kiln for auditing or refreshing it.** Every line in the file costs context-window tokens forever, across every session the plugin is installed in — bloat is a multiplicative, permanent tax. The consumer-repo template (`plugin-kiln/scaffold/CLAUDE.md`) has drifted and is "not exactly relevant anymore" per the maintainer. Kiln should own a mechanism for keeping CLAUDE.md useful over time, not rely on occasional manual audits.
2. **`/kiln:kiln-feedback` captures a description and classification, but it does not interview the user about the underlying improvement.** The current skill hard-gates on classification ambiguity but does not proactively draw out the shape of the change the user wants executed. A feedback entry filed without that depth produces a thin PRD downstream — the distill step can only work with what it has. The skill should run a short structured interview before writing, so feedback files carry enough signal to drive the next PRD accurately.

The tactical backlog entry for a first CLAUDE.md audit pass (`.kiln/issues/2026-04-23-claude-md-audit-and-prune.md`) reinforces the strategic feedback — it is exactly the kind of work the audit mechanism should make routine rather than ad-hoc.

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|-------------|--------|------|--------------|------------------|
| 1 | [CLAUDE.md refresh/audit mechanism](../../../.kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md) | `.kiln/feedback/` | feedback | — | high / architecture |
| 2 | [/kiln:kiln-feedback should interview the user before writing](../../../.kiln/feedback/2026-04-23-feedback-should-interview-me-about.md) | `.kiln/feedback/` | feedback | — | medium / ergonomics |
| 3 | [Audit and prune CLAUDE.md for kiln — first audit pass](../../../.kiln/issues/2026-04-23-claude-md-audit-and-prune.md) | `.kiln/issues/` | issue | — | medium / documentation |

## Problem Statement

Kiln currently has no product-owned mechanism for maintaining its own context artifacts. CLAUDE.md accumulates across every feature branch — new sections get added, old sections go stale, the "Recent Changes" and "Active Technologies" blocks grow without bound, and the consumer-repo template drifts away from relevance. Every consumer session pays the bloat cost in context tokens; every consumer onboarding pays the cost in confusion when the scaffolded CLAUDE.md describes a state that no longer matches the plugin.

In parallel, `/kiln:kiln-feedback` captures feedback too shallowly to drive the next PRD. When the user files "X should do Y", the skill writes the one-liner but does not ask what "done" looks like, who triggers it, what the outcome shape should be, or what scope applies. The distill step downstream then produces a PRD with holes that either block the build or force the pipeline to guess — this was visible in this very conversation, where the CLAUDE.md feedback required a 5-question interview from the team lead before it was bundle-ready.

Both problems are the same pattern: **kiln improves its users' product-development mechanics but does not apply the same mechanical discipline to itself.** This PRD adds two specific mechanisms — a CLAUDE.md audit/refresh flow, and an interview mode on `/kiln:kiln-feedback` — that close this gap.

## Goals

**CLAUDE.md audit (feedback-led)**:
- Give kiln a first-class way to audit and propose edits to CLAUDE.md — both in the source repo and in consumer repos via the scaffold template.
- Ground the audit in a documented, versioned rubric for "useful CLAUDE.md content" that can evolve independently of the code that reads it.
- Produce review-shaped output (git diff) rather than auto-applied edits — the maintainer keeps final say.
- Rewrite the consumer-repo template as a one-time cleanup, because the current version has drifted far enough that incremental pruning is insufficient.

**Feedback interview (feedback-led)**:
- Make `/kiln:kiln-feedback` run a short structured interview before writing, so every feedback file has enough signal to drive a coherent PRD without requiring follow-up interrogation at distill time.

**Tactical goal (issue-led)**:
- Execute the first CLAUDE.md audit pass against the source repo immediately after the mechanism lands — prove the mechanism on the accumulated bloat that motivated this feature.

## Non-Goals

- Automating the audit on every commit or on a timer — the audit is invoked on demand (by the maintainer or by `/kiln:kiln-doctor`), not continuously.
- Auto-applying audit-proposed edits. Every edit goes through human review. No "apply all" mode in v1.
- Rewriting every consumer repo's existing CLAUDE.md in the field. The scaffold template gets rewritten, and future `kiln init` invocations pick up the new template. Existing consumer CLAUDE.mds are the consumer's responsibility to audit (using the same mechanism).
- Expanding `/kiln:kiln-feedback` into a full PRD composer. The interview is short (3–6 questions max) and captures structured signal — it does not replace `/kiln:kiln-distill` or `/kiln:kiln-create-prd`.
- Changing the CLAUDE.md-is-committed policy or converting it to a generated artifact. The file stays human-authored; the audit proposes edits, it does not take ownership.

## Requirements

### Functional Requirements

**CLAUDE.md audit mechanism (feedback-derived, highest severity)**:

- **FR-001 (from: `.kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md`)** The kiln plugin MUST provide a way to audit CLAUDE.md that the maintainer can invoke ad-hoc, AND that runs as part of `/kiln:kiln-doctor`'s structural-validation sweep. The implementation MAY be a dedicated skill (e.g., `/kiln:kiln-claude-audit`), an extension of an existing skill, or a `kiln-doctor` subcheck — plan phase picks the shape.
- **FR-002 (from: same)** Before implementation, a **research phase** MUST produce and commit a `usefulness rubric` artifact (proposed location: `plugin-kiln/rubrics/claude-md-usefulness.md`). The rubric is the versioned, evolvable definition of what "useful CLAUDE.md content" means for this plugin. The audit skill reads the rubric at invocation — it does NOT hardcode the rules.
- **FR-003 (from: same)** The rubric MUST cover at least these signal types: (a) **load-bearing** — grep references from skills / agents / hooks / workflows / templates (if any of them reads or cites a specific CLAUDE.md section, that section stays); (b) **editorial** — LLM-judgment flags for stale or duplicated content against `docs/PRD.md` and `.specify/memory/constitution.md`; (c) **freshness heuristics** — migration notices older than a configurable threshold become removal candidates; "Recent Changes" and "Active Technologies" entries beyond the last N are archival candidates. Plan phase may add or refine signal types.
- **FR-004 (from: same)** The audit output MUST be a `git diff`-style preview saved to `.kiln/logs/claude-md-audit-<YYYY-MM-DD-HHMMSS>.md`. The audit skill MUST NOT write edits directly to CLAUDE.md — it proposes only. The maintainer reviews the diff, then applies it manually (or via a separate accept command — out of scope for v1 unless plan phase finds it trivial).
- **FR-005 (from: same)** The audit MUST cover BOTH the source-repo `CLAUDE.md` AND the consumer-repo template `plugin-kiln/scaffold/CLAUDE.md`. When invoked in the plugin source repo, both are audited; when invoked in a consumer repo, only that repo's `CLAUDE.md` is audited (the scaffold lives under the cached plugin, not the consumer's repo).
- **FR-006 (from: same)** As a one-time cleanup, the `plugin-kiln/scaffold/CLAUDE.md` template MUST be rewritten from scratch to reflect the current plugin architecture (the maintainer's words: "not exactly relevant anymore"). This rewrite happens during this feature's implementation, not deferred. The new template is the starting baseline for all future `kiln init` scaffolds.

**`/kiln:kiln-feedback` interview mode (feedback-derived, lower severity)**:

- **FR-007 (from: `.kiln/feedback/2026-04-23-feedback-should-interview-me-about.md`)** `/kiln:kiln-feedback` MUST run a short structured interview before writing the feedback file. The interview adds 3–6 questions on top of the existing classification-ambiguity gate. Question set is static but context-sensitive — different area (mission / scope / ergonomics / architecture) may surface slightly different question sets.
- **FR-008 (from: same)** Minimum interview coverage, applicable to any area:
  - What does "done" look like for this improvement? (what's the observable outcome?)
  - Who triggers it and when? (ad-hoc command, hook, part of existing skill, background agent…)
  - What's the scope? (just this repo, consumer repos too, other plugins…)
  - Is there an existing tactical backlog entry that pairs with this feedback?
  - (Area-specific) 1–2 additional questions drawn from the area taxonomy.
- **FR-009 (from: same)** The interview answers MUST be captured in the feedback file body (not frontmatter) as a structured section — e.g., `## Interview` with sub-headings per question. The raw feedback description stays at the top; the interview answers follow. `/kiln:kiln-distill` reads the interview section to build richer PRD narratives.
- **FR-010 (from: same)** The interview MUST be skippable via a single explicit opt-out at the prompt (e.g., "skip interview — I just want to capture the one-liner"). Skipping writes a file with no `## Interview` section, same shape as today's skill. The interview is the new default; skipping is the escape hatch.

**Tactical — first audit pass (issue-derived)**:

- **FR-011 (from: `.kiln/issues/2026-04-23-claude-md-audit-and-prune.md`)** Immediately after the audit mechanism (FR-001..FR-006) lands, a smoke-test-style **first pass** MUST be executed against the source repo's CLAUDE.md. The pass uses the new audit skill, the resulting diff is reviewed, and any non-controversial edits are applied in the same PR. This proves the mechanism on real accumulated bloat and is the baseline-setting audit.

### Non-Functional Requirements

- **NFR-001** No new runtime dependencies. All work is Bash + skill-body markdown + optional LLM judgment via agent steps.
- **NFR-002** The audit skill MUST be idempotent — running it twice on an unchanged CLAUDE.md produces byte-identical diffs (empty in the no-change case). Same policy `/kiln:kiln-next` follows.
- **NFR-003** The interview step in `/kiln:kiln-feedback` MUST NOT break the skill's existing "no wheel workflow, no MCP writes, no background sync" contract. The interview happens inline in main chat before the file write; no new side effects.
- **NFR-004** The usefulness rubric MUST be versioned and discoverable — plan phase picks the exact path, but it must be grep-able from elsewhere in the repo so skill authors can reference it.

## User Stories

- **US-001** As a maintainer who has just finished a feature pipeline, I want to run `/kiln:kiln-doctor` and have it tell me whether CLAUDE.md has drifted — with a concrete diff I can review and apply — so I don't discover the bloat only when a consumer complains about context costs. (FR-001, FR-004)
- **US-002** As a maintainer deciding what belongs in CLAUDE.md, I want a written, versioned rubric that encodes "useful" for this plugin, so I don't re-derive the criteria from memory every time. (FR-002, FR-003)
- **US-003** As a new consumer running `kiln init`, I want the scaffolded CLAUDE.md to reflect the plugin's actual current architecture so I'm not onboarded to yesterday's state. (FR-005, FR-006)
- **US-004** As a maintainer filing strategic feedback, I want the skill to interview me about what "done" looks like, so the feedback file is rich enough to drive a coherent PRD without needing the team-lead (or me next session) to re-interrogate. (FR-007, FR-008, FR-009)
- **US-005** As a maintainer who already knows exactly what the PRD should say and just wants to jot the one-liner, I want a visible skip-interview option so I'm not forced through the interview every time. (FR-010)

## Success Criteria

- **SC-001 Audit mechanism exists and runs clean on empty case.** Running the audit skill on a CLAUDE.md that perfectly matches the rubric produces a zero-diff output file. Verified by: fixture with a hand-crafted minimal CLAUDE.md + audit invocation + empty-diff check.
- **SC-002 Audit catches real bloat.** Running the audit skill against the current source-repo CLAUDE.md produces a non-empty diff identifying at least: (a) the "Migration Notice" block (candidate for removal — the rename is months old), (b) entries in "Recent Changes" older than the configurable threshold, (c) at least one section duplicated in docs/PRD.md or constitution.md. Verified by: the FR-011 first pass output contains these categories.
- **SC-003 Consumer template is rewritten.** `plugin-kiln/scaffold/CLAUDE.md` has been fully rewritten in this PR. Verified by: `git log -p plugin-kiln/scaffold/CLAUDE.md` in the PR shows a substantial rewrite, not just pruning.
- **SC-004 Rubric artifact exists and is discoverable.** The rubric file exists at the plan-phase-chosen path, is referenced from the audit skill's body, and a grep for the rubric path finds at least one non-skill reference (docs or readme). Verified by: file exists + `grep -rn <rubric-path>` finds ≥1 additional reference.
- **SC-005 Interview runs by default.** Invoking `/kiln:kiln-feedback "<description>"` prompts for 3–6 questions before writing. Verified by: a scripted run + observing the question count.
- **SC-006 Interview output is captured.** The resulting `.kiln/feedback/<file>.md` contains a `## Interview` section with the user's answers. Verified by: grep `## Interview` in the output file after a full-interview run.
- **SC-007 Skip opt-out works.** Invoking `/kiln:kiln-feedback` and choosing skip produces a file with the body equal to the raw description and no `## Interview` section. Verified by: scripted skip-interview run + content-check on the output file.
- **SC-008 First audit pass landed.** The PR that delivers this feature also contains the commit applying the first audit pass's accepted edits to the source-repo CLAUDE.md. Verified by: `git log -p CLAUDE.md` in the PR shows pruning/restructuring commits.

## Tech Stack

Inherited from the parent product — no additions:

- Markdown (skill definitions, rubric artifact)
- Bash 5.x (audit skill body, diff generation via `git diff --no-index` or equivalent)
- Optional LLM judgment via agent steps for the "editorial" signal in FR-003 — same pattern `/kiln:kiln-audit` uses today
- `grep`, `jq`, standard POSIX utilities

## Risks & Open Questions

- **Rubric drift.** If the rubric is versioned separately from the plugin version, it can drift from the skill's actual logic. Plan phase should decide whether the rubric is embedded in the plugin (version-locked) or user-customizable in the consumer repo (user-override pattern, like `.shelf-config`). Recommend: plugin-embedded default + consumer-override hook for customization.
- **"Editorial" LLM calls on every doctor run**. FR-003's editorial signal (LLM judgment for stale/duplicated) could be expensive if it fires every time `/kiln:kiln-doctor` runs. Plan phase should decide: (a) gate editorial behind a flag, (b) cache the LLM judgment in `.kiln/logs/` and skip re-runs when CLAUDE.md is unchanged, or (c) split the doctor check (cheap greppy checks every run; editorial check only on the dedicated audit skill).
- **Scaffold template rewrite scope**. FR-006 says "rewrite from scratch" but the new template still has to be useful. Plan phase should decide: minimal skeleton only (let consumers add their own context), or a curated template that names the plugins + their canonical commands. Recommend: minimal skeleton; the per-plugin READMEs (separate backlog item `.kiln/issues/2026-04-22-plugin-documentation.md`) carry the canonical-commands surface.
- **Interview question fatigue**. If every `/kiln:kiln-feedback` invocation fires a 6-question interview, the maintainer may learn to always skip. FR-008 caps the count at 6, but plan phase should consider a shorter default (3 questions) with 3 additional area-specific questions only when the area explicitly triggers them.
- **Consumer repo audit UX**. In a consumer repo, the audit skill reads only the consumer's CLAUDE.md, but the rubric lives under the cached plugin. If a consumer wants to override a rubric rule, where does the override live? Plan phase should specify a `.kiln/claude-md-audit.config` or similar pattern.
- **Interview skip semantics**. FR-010 says skip is a single explicit opt-out. Plan phase should decide: is the opt-out the LAST option at the first prompt, or a dedicated slash-command flag (`/kiln:kiln-feedback --no-interview "..."`)? Given the precedent set by the clay-ideation-polish PRD (no CLI flags for interactive skills), lean toward the in-prompt opt-out.

## Implementation Ordering Note

The implementation naturally sequences as:
1. **Part A — Research + Rubric** (FR-002, FR-003) — documentation/artifact, no code. Low risk, high leverage. Land first.
2. **Part B — Audit skill + kiln-doctor integration** (FR-001, FR-004, FR-005) — the core mechanism.
3. **Part C — Scaffold rewrite** (FR-006) — one-time cleanup, parallelizable with Part B.
4. **Part D — Feedback interview mode** (FR-007–FR-010) — independent of the CLAUDE.md work; can be done by a second implementer in parallel.
5. **Part E — First audit pass + rubric cross-reference grep gate** (FR-011, SC-002) — executed after Part B lands.

This sequencing lets the pipeline split into two parallel tracks (CLAUDE.md audit track + feedback interview track), per the clay-ideation-polish precedent. Plan phase may prefer to keep it serial if coordination overhead outweighs the parallelism benefit.
